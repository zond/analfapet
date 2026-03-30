// --- Offline caching ---
const CACHE_NAME = 'analfapet-v1';

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Don't cache API calls or Firebase requests
  if (url.origin !== self.location.origin) return;
  if (event.request.method !== 'GET') return;

  event.respondWith(
    caches.match(event.request).then((cached) => {
      const fetched = fetch(event.request).then((response) => {
        if (response.ok) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        }
        return response;
      }).catch(() => cached);

      return cached || fetched;
    })
  );
});

// --- Firebase Cloud Messaging ---
importScripts("https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyDdsNrnheLnhAe5fPJNkQo86f40DgBdg5I",
  appId: "1:245672555479:web:01dd2824ac0ff9e94e9192",
  messagingSenderId: "245672555479",
  projectId: "fcm-switch",
  authDomain: "fcm-switch.firebaseapp.com",
  storageBucket: "fcm-switch.firebasestorage.app",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const type = payload.data?.type || 'message';
  const sender = payload.data?.senderName || 'Someone';

  let title = 'Analfapet';
  let body = 'New message';

  switch (type) {
    case 'friendRequest':
      title = 'Friend request';
      body = `${sender} added you as a friend`;
      break;
    case 'invite':
      title = 'Game invite';
      body = `${sender} invited you to a game`;
      break;
    case 'move':
      title = 'Your turn!';
      body = `${sender} played a move`;
      break;
    case 'hurry':
      title = 'Hurry up!';
      body = `${sender} is waiting for your move`;
      break;
    case 'accept':
      title = 'Game starting';
      body = `${sender} accepted the invite`;
      break;
  }

  return self.registration.showNotification(title, {
    body,
    icon: 'icons/Icon-192.png',
    data: payload.data,
  });
});

// When user clicks a notification, focus the tab and forward the data
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data;

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      // Try to focus an existing tab
      for (const client of clientList) {
        if (client.url.includes('analfapet') && 'focus' in client) {
          client.focus();
          // Forward the message data so the app can process it
          if (data) client.postMessage({ type: 'notification-click', data: data });
          return;
        }
      }
      // No existing tab — open a new one with data in the URL fragment
      if (clients.openWindow) {
        const encoded = data ? encodeURIComponent(JSON.stringify(data)) : '';
        return clients.openWindow('./#notification=' + encoded);
      }
    })
  );
});
