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
