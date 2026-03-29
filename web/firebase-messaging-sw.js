importScripts("https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyDdsNrnheLnhAe5fPJNkQo56f40DgBdg5I",
  appId: "1:245672555479:web:01dd2824ac0ff9e94e9192",
  messagingSenderId: "245672555479",
  projectId: "fcm-switch",
  authDomain: "fcm-switch.firebaseapp.com",
  storageBucket: "fcm-switch.firebasestorage.app",
});

const messaging = firebase.messaging();
