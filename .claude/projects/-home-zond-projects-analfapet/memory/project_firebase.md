---
name: Firebase project
description: Shared Firebase project "fcm-switch" used as FCM relay across multiple apps
type: project
---

Firebase project "fcm-switch" is a shared FCM communication layer used across multiple apps, not just Analfapet.

**Why:** User wants a single Firebase project for inter-app FCM messaging rather than per-app projects.

**How to apply:** Don't assume this Firebase project is Analfapet-specific. Keep Firestore structure namespaced if needed to avoid collisions with other apps.
