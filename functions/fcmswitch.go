package fcmswitch

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/db"
	"firebase.google.com/go/v4/messaging"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
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

	ctx := r.Context()
	ref := dbClient.NewRef("players/" + req.UUID)

	var existing playerRecord
	if err := ref.Get(ctx, &existing); err != nil {
		http.Error(w, fmt.Sprintf("db read: %v", err), http.StatusInternalServerError)
		return
	}

	if existing.Secret != "" {
		// Existing registration — verify secret
		if existing.Secret != req.Secret {
			http.Error(w, "invalid secret", http.StatusForbidden)
			return
		}
		// Update token
		if err := ref.Update(ctx, map[string]interface{}{"token": req.Token}); err != nil {
			http.Error(w, fmt.Sprintf("db update: %v", err), http.StatusInternalServerError)
			return
		}
	} else {
		// First registration
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

	_, err := msgClient.Send(ctx, &messaging.Message{
		Token: player.Token,
		Data:  req.Data,
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

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"success": true})
}
