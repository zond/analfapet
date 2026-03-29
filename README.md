# Analfapet

A Wordfeud-style Swedish word game built with Flutter for the web.

Game state lives entirely on each player's device. Moves are relayed via Firebase Cloud Messaging. Each move includes a turn sequence number and board-state hash for validation. Tile draws use a shared seeded PRNG so both clients compute identical sequences independently.

Player identity is a locally generated UUID. The only server-side state is a Firestore document per player mapping UUID to current FCM token. Players add friends via QR code or by sharing their UUID.

## Setup

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) (stable channel)
- A Firebase project with Firestore and FCM enabled

### Wordlist

The wordlist is not included in the repository. Download it from [axki/saol-wordlist](https://github.com/axki/saol-wordlist/tree/master/output), gzip it, and place it in the assets directory:

```bash
# After downloading the wordlist file:
gzip -c wordlist.txt > assets/wordlist.txt.gz
```

### Firebase

Configure Firebase for your project:

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=YOUR_PROJECT --platforms=web
```

### Run

```bash
flutter pub get
flutter run -d chrome
```
