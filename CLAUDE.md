# Claude Code Project Guide

## Build, Deploy, Push Flow

1. Make changes
2. Run `./deploy-web.sh` — builds Flutter web, stamps service worker, deploys to gh-pages. If build fails, fix it. If it succeeds, the site is live.
3. `git add` + `git commit` + `git push` — pushes source code to main

The deploy script serves as both build verification and deployment. No need for separate `flutter build` commands.

## Cloud Functions

Go Cloud Functions in `functions/`. Deploy with:
```bash
cd functions && ./deploy.sh
```
The deploy script skips functions that haven't changed (compares source hash via labels).

## Project Structure

- `lib/models/` — Game state, board, tiles, moves, remote game
- `lib/services/` — FCM, dictionary, friends, player identity, remote game controller, message codec, toast
- `lib/screens/` — Game, friends, remote games, QR scanner
- `lib/widgets/` — Board widget, tile rack widget
- `functions/` — Go Cloud Functions (Register, Send, Inbox)
- `web/` — index.html, service worker, manifest

## Architecture

- **All game state is local** (SharedPreferences). No server-side game storage.
- **FCM is the sole communication channel** between players, relayed via Cloud Functions.
- **Binary protocol**: 2 message types (friend request 0x01, game state 0x02), base64-encoded.
- **Every game message is a full state snapshot** — self-healing by design.
- **Inbox**: Cloud Function stores messages in Realtime Database for pull-based retrieval when FCM push is missed.
- **Realtime Database**: only stores UUID→FCM token mapping + inbox. Locked to admin-only access.
- **Deterministic replay**: seed + ordered moves = identical game state on all clients.

## Key Conventions

- Board cell colors are green — don't change them when changing the app background.
- Swedish tile set (no Q or W). Blank tile picker: ABCDEFGHIJKLMNOPRSTUVXYZÅÄÖ.
- `_userRackOrder` tracks the user's tile arrangement separately from GameState.
- Player order is sorted by UUID after all players accept (deterministic, idempotent).
- Toast notifications use overlay-based `showToast()` from `lib/services/toast.dart`.
- iOS requires "Add to Home Screen" before remote games/friends work (service worker + notifications).
