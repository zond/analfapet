package fcmswitch

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"regexp"
	"sort"
	"sync"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/db"
	"firebase.google.com/go/v4/messaging"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
)

var uuidRegex = regexp.MustCompile(`^[0-9a-fA-F-]{36}$`)

const (
	maxInboxMessages = 128
	inboxTTL         = 7 * 24 * time.Hour
)

var (
	dbClient  *db.Client
	msgClient *messaging.Client
	once      sync.Once
)

func initClients() {
	once.Do(func() {
		ctx := context.Background()
		app, err := firebase.NewApp(ctx, nil)
		if err != nil {
			log.Fatalf("firebase.NewApp: %v", err)
		}
		dbClient, err = app.DatabaseWithURL(ctx, "https://fcm-switch-default-rtdb.europe-west1.firebasedatabase.app")
		if err != nil {
			log.Fatalf("app.Database: %v", err)
		}
		msgClient, err = app.Messaging(ctx)
		if err != nil {
			log.Fatalf("app.Messaging: %v", err)
		}
	})
}

type playerRecord struct {
	Token  string `json:"token"`
	Secret string `json:"secret"`
}

type registerRequest struct {
	UUID   string `json:"uuid"`
	Token  string `json:"token"`
	Secret string `json:"secret"`
}

type sendRequest struct {
	TargetUUID string            `json:"targetUuid"`
	Data       map[string]string `json:"data"`
}

type inboxRequest struct {
	UUID   string `json:"uuid"`
	Secret string `json:"secret"`
}

type inboxMessage struct {
	Data      map[string]string `json:"data"`
	Timestamp int64             `json:"timestamp"`
}

func cors(w http.ResponseWriter, r *http.Request) bool {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return true
	}
	return false
}

func init() {
	functions.HTTP("Register", handleRegister)
	functions.HTTP("Send", handleSend)
	functions.HTTP("Inbox", handleInbox)
}

func handleRegister(w http.ResponseWriter, r *http.Request) {
	if cors(w, r) {
		return
	}
	initClients()

	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}

	var req registerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}
	if req.UUID == "" || req.Token == "" || req.Secret == "" {
		http.Error(w, "uuid, token, and secret are required", http.StatusBadRequest)
		return
	}
	if !uuidRegex.MatchString(req.UUID) {
		http.Error(w, "invalid uuid format", http.StatusBadRequest)
		return
	}

	ctx := r.Context()
	ref := dbClient.NewRef("players/" + req.UUID)

	var existing playerRecord
	if err := ref.Get(ctx, &existing); err != nil {
		http.Error(w, fmt.Sprintf("db read: %v", err), http.StatusInternalServerError)
		return
	}

	if existing.Secret != "" {
		if existing.Secret != req.Secret {
			http.Error(w, "invalid secret", http.StatusForbidden)
			return
		}
		if err := ref.Update(ctx, map[string]interface{}{"token": req.Token}); err != nil {
			http.Error(w, fmt.Sprintf("db update: %v", err), http.StatusInternalServerError)
			return
		}
	} else {
		if err := ref.Set(ctx, playerRecord{Token: req.Token, Secret: req.Secret}); err != nil {
			http.Error(w, fmt.Sprintf("db set: %v", err), http.StatusInternalServerError)
			return
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"success": true})
}

func handleSend(w http.ResponseWriter, r *http.Request) {
	if cors(w, r) {
		return
	}
	initClients()

	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}

	var req sendRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}
	if req.TargetUUID == "" || req.Data == nil {
		http.Error(w, "targetUuid and data are required", http.StatusBadRequest)
		return
	}
	if !uuidRegex.MatchString(req.TargetUUID) {
		http.Error(w, "invalid targetUuid format", http.StatusBadRequest)
		return
	}

	ctx := r.Context()

	var player playerRecord
	if err := dbClient.NewRef("players/" + req.TargetUUID + "/token").Get(ctx, &player.Token); err != nil {
		http.Error(w, fmt.Sprintf("db read: %v", err), http.StatusInternalServerError)
		return
	}
	if player.Token == "" {
		http.Error(w, "player not found", http.StatusNotFound)
		return
	}

	// Send via FCM
	_, err := msgClient.Send(ctx, &messaging.Message{
		Token: player.Token,
		Data:  req.Data,
		Webpush: &messaging.WebpushConfig{
			Headers: map[string]string{
				"Urgency": "high",
			},
		},
	})
	if err != nil {
		if messaging.IsRegistrationTokenNotRegistered(err) {
			dbClient.NewRef("players/" + req.TargetUUID).Delete(ctx)
			http.Error(w, "player token expired", http.StatusNotFound)
			return
		}
		http.Error(w, fmt.Sprintf("send: %v", err), http.StatusInternalServerError)
		return
	}

	// Also append to inbox for pull-based retrieval
	inboxRef := dbClient.NewRef("inbox/" + req.TargetUUID)
	now := time.Now().UnixMilli()
	msg := inboxMessage{
		Data:      req.Data,
		Timestamp: now,
	}
	if _, err := inboxRef.Push(ctx, msg); err != nil {
		// Non-fatal — FCM already sent
		log.Printf("inbox append failed for %s: %v", req.TargetUUID, err)
	}

	// Lazy enforce size + age bounds on write
	go func() {
		bgCtx := context.Background()
		var msgs map[string]inboxMessage
		if err := inboxRef.Get(bgCtx, &msgs); err != nil {
			return
		}
		cutoff := now - int64(inboxTTL/time.Millisecond)
		updates := map[string]interface{}{}
		type entry struct {
			key string
			ts  int64
		}
		var valid []entry
		for k, m := range msgs {
			if m.Timestamp < cutoff {
				updates[k] = nil // expired
			} else {
				valid = append(valid, entry{k, m.Timestamp})
			}
		}
		// If over max, remove oldest
		if len(valid) > maxInboxMessages {
			// Sort by timestamp ascending
			for i := 0; i < len(valid); i++ {
				for j := i + 1; j < len(valid); j++ {
					if valid[j].ts < valid[i].ts {
						valid[i], valid[j] = valid[j], valid[i]
					}
				}
			}
			for i := 0; i < len(valid)-maxInboxMessages; i++ {
				updates[valid[i].key] = nil
			}
		}
		if len(updates) > 0 {
			inboxRef.Update(bgCtx, updates)
		}
	}()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"success": true})
}

// handleInbox returns all pending messages for a player and clears the inbox.
func handleInbox(w http.ResponseWriter, r *http.Request) {
	if cors(w, r) {
		return
	}
	initClients()

	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}

	var req inboxRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}
	if req.UUID == "" || req.Secret == "" {
		http.Error(w, "uuid and secret are required", http.StatusBadRequest)
		return
	}
	if !uuidRegex.MatchString(req.UUID) {
		http.Error(w, "invalid uuid format", http.StatusBadRequest)
		return
	}

	ctx := r.Context()

	// Verify secret
	var player playerRecord
	if err := dbClient.NewRef("players/" + req.UUID).Get(ctx, &player); err != nil {
		http.Error(w, fmt.Sprintf("db read: %v", err), http.StatusInternalServerError)
		return
	}
	if player.Secret != req.Secret {
		http.Error(w, "invalid secret", http.StatusForbidden)
		return
	}

	// Read inbox
	inboxRef := dbClient.NewRef("inbox/" + req.UUID)
	var messages map[string]inboxMessage
	if err := inboxRef.Get(ctx, &messages); err != nil {
		http.Error(w, fmt.Sprintf("db read: %v", err), http.StatusInternalServerError)
		return
	}

	// Filter expired, collect valid sorted by timestamp
	cutoff := time.Now().Add(-inboxTTL).UnixMilli()
	type validMsg struct {
		data map[string]string
		ts   int64
	}
	var valid []validMsg
	var keysToDelete []string

	for key, msg := range messages {
		if msg.Timestamp < cutoff {
			keysToDelete = append(keysToDelete, key)
			continue
		}
		valid = append(valid, validMsg{msg.Data, msg.Timestamp})
		keysToDelete = append(keysToDelete, key)
	}

	sort.Slice(valid, func(i, j int) bool { return valid[i].ts < valid[j].ts })
	result := make([]map[string]string, len(valid))
	for i, v := range valid {
		result[i] = v.data
	}

	// Clear processed + expired messages
	if len(keysToDelete) > 0 {
		updates := make(map[string]interface{})
		for _, key := range keysToDelete {
			updates[key] = nil
		}
		if err := inboxRef.Update(ctx, updates); err != nil {
			log.Printf("inbox cleanup failed for %s: %v", req.UUID, err)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"messages": result,
	})
}
