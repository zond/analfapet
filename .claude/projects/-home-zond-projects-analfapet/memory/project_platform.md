---
name: Platform target
description: Analfapet targets web (not mobile). No NFC — friend sharing via QR or UUID only.
type: project
---

Web app, not Android/iOS. FCM via web push.

**Why:** User decision to simplify deployment.

**How to apply:** No NFC. Friend-adding is QR code or sharing UUID. Use web-compatible packages only. FCM needs VAPID key + service worker for web.
