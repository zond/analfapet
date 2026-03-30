---
name: Remote game design
description: Architecture for remote multiplayer — all state local, FCM relay only, no Firestore game storage
type: project
---

Remote games use FCM as pure message relay. All game state is local.

**Flow:**
1. Creator picks friends, creates game with random seed, sends invite via FCM to all
2. Each invitee stores invite locally, shown in "Remote games" list
3. Accepting sends FCM to all other players
4. Game starts automatically when all players have accepted
5. First player (determined by seed) is notified it's their turn
6. Each finished move is FCM'd to all other players
7. "Hurry up" button pings a slow player; when they open the game, current state is sent to all (implicit state sync / missed FCM recovery)

**FCM message types:** invite, accept, deny, move, hurry, state_sync

**Local storage:** SharedPreferences stores list of remote games with status (invited/active/finished), seed, player list, and move history.

**Why:** Minimal server infrastructure — Firestore only stores UUID→FCM token mapping. No game state server-side.

**How to apply:** Never store game state in Firestore. All game data lives on device. FCM is the only communication channel between players.
