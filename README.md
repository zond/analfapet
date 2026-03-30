# Analfapet

**[Play now](https://zond.github.io/analfapet/)**

A Wordfeud-style Swedish word game built with Flutter for the web.

## Architecture

Game state lives entirely on each player's device. Moves are relayed via Firebase Cloud Messaging through two Go Cloud Functions that act as an FCM relay ("fcm-switch"). Each game message is a binary-packed, base64-encoded full game state — self-healing by design.

Tile draws use a shared seeded PRNG so both clients compute identical sequences independently. The game is fully playable offline (local games), and remote games sync automatically when connectivity returns.

### Infrastructure

- **Cloud Functions** (Go): `Register` (UUID + FCM token + secret) and `Send` (FCM relay)
- **Realtime Database**: stores only UUID-to-token mapping, locked to admin-only access
- **FCM**: sole communication channel between players
- **No Firestore**, no authentication, no hosting backend

### Message protocol

Only 2 message types, binary-packed and base64-encoded:
- `0x01`: Friend request (UUID + name)
- `0x02`: Full game state (players, acceptance status, all moves)

Every game message carries the complete state. No separate invite/accept/move/sync messages — any message can bring a client fully up to date.

## Setup

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) (stable channel)
- [Go](https://go.dev/dl/) (for Cloud Functions)
- A Firebase project with FCM and Realtime Database enabled (Blaze plan)
- [gcloud CLI](https://cloud.google.com/sdk/docs/install)

### Wordlist

The wordlist is not included in the repository. Download [`saol_wordlist.txt`](https://github.com/axki/saol-wordlist/raw/refs/heads/master/output/saol_wordlist.txt) from [axki/saol-wordlist](https://github.com/axki/saol-wordlist/tree/master/output) and place it in the assets directory:

```bash
mkdir -p assets
curl -fsSL -o assets/wordlist.txt "https://github.com/axki/saol-wordlist/raw/refs/heads/master/output/saol_wordlist.txt"
```

### Firebase

Configure Firebase for your project:

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=YOUR_PROJECT --platforms=web
```

### Cloud Functions

Deploy the two Go Cloud Functions:

```bash
cd functions

gcloud functions deploy Register \
  --gen2 --runtime=go126 --trigger-http --allow-unauthenticated \
  --entry-point=Register --source=. --project=YOUR_PROJECT --region=europe-west1

gcloud functions deploy Send \
  --gen2 --runtime=go126 --trigger-http --allow-unauthenticated \
  --entry-point=Send --source=. --project=YOUR_PROJECT --region=europe-west1
```

Update the functions base URL in `lib/services/fcm_service.dart` and the Realtime Database URL in `functions/fcmswitch.go`.

### Run

```bash
flutter pub get
flutter run -d chrome
```
