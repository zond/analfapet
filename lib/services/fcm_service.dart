import 'dart:convert';
import 'dart:js_interop';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:web/web.dart' as web;

const _vapidKey = 'BADlJWLuNnXTe6VG4fCEhz-NdXSh5zElySUYFcJoOSRO8Hzs8MDNM_mN1FGb8TJvEZ5T26bKHA_f5irGG74m0tU';

class FcmService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _token;

  String? get token => _token;

  Future<void> init(String playerId) async {
    try {
      print('[FCM] Requesting permission...');
      final settings = await _messaging.requestPermission();
      print('[FCM] Permission: ${settings.authorizationStatus}');

      // Register service worker at correct path for subpath deploys (e.g. GitHub Pages)
      final baseHref = web.document.querySelector('base')?.getAttribute('href') ?? '/';
      final swUrl = '${baseHref}firebase-messaging-sw.js';
      print('[FCM] Registering service worker at $swUrl');
      await web.window.navigator.serviceWorker.register(swUrl.toJS).toDart;
      print('[FCM] Service worker registered, waiting for ready...');
      final swReg = await web.window.navigator.serviceWorker.ready.toDart;
      print('[FCM] Service worker ready');

      // Use JS interop to call getToken with our service worker registration,
      // bypassing the Flutter plugin which doesn't expose this parameter.
      print('[FCM] Getting token...');
      _token = await _getTokenViaJs(swReg);
      print('[FCM] Token: ${_token != null ? '${_token!.substring(0, 20)}...' : 'null'}');

      if (_token != null) {
        await _registerToken(playerId, _token!);
      }
      _messaging.onTokenRefresh.listen((token) {
        print('[FCM] Token refreshed');
        _token = token;
        _registerToken(playerId, token);
      });
    } catch (e) {
      print('[FCM] Init failed (non-fatal): $e');
    }
  }

  /// Call the Firebase JS SDK's getToken() with our service worker registration.
  Future<String?> _getTokenViaJs(web.ServiceWorkerRegistration swReg) async {
    // The Flutter firebase_messaging_web plugin stores the JS messaging instance.
    // We can access it via the global firebase_messaging namespace, or we can
    // evaluate JS directly. Simplest: use eval to call the Firebase JS API.
    final result = await _jsGetTokenWithSW(swReg, _vapidKey).toDart;
    return result?.toDart;
  }

  Future<void> _registerToken(String playerId, String token) async {
    print('[FCM] Registering token for player $playerId...');
    await _firestore.collection('players').doc(playerId).set({
      'fcmToken': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    print('[FCM] Token registered in Firestore');
  }

  void onMessageHandler(void Function(Map<String, dynamic> data) handler) {
    FirebaseMessaging.onMessage.listen((message) {
      print('[FCM] Message received: ${message.data}');
      if (message.data.isNotEmpty) {
        handler(message.data);
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      print('[FCM] Message opened app: ${message.data}');
      if (message.data.isNotEmpty) {
        handler(message.data);
      }
    });
  }

  Future<String?> getTokenForPlayer(String playerId) async {
    final doc = await _firestore.collection('players').doc(playerId).get();
    return doc.data()?['fcmToken'] as String?;
  }

  /// Send data to a single player via their Firestore inbox.
  Future<void> sendToPlayer(String targetPlayerId, Map<String, dynamic> data) async {
    await _firestore
        .collection('players')
        .doc(targetPlayerId)
        .collection('inbox')
        .add({
      'data': jsonEncode(data),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Broadcast data to multiple players (excluding self).
  Future<void> broadcast(List<String> playerIds, String myId, Map<String, dynamic> data) async {
    for (final id in playerIds) {
      if (id != myId) {
        await sendToPlayer(id, data);
      }
    }
  }

  Stream<List<Map<String, dynamic>>> listenForMoves(String playerId) {
    return _firestore
        .collection('players')
        .doc(playerId)
        .collection('inbox')
        .orderBy('timestamp')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = jsonDecode(doc['data'] as String) as Map<String, dynamic>;
              doc.reference.delete();
              return data;
            }).toList());
  }
}

/// Uses the compat Firebase JS SDK (loaded by the service worker script in index.html)
/// to get the token with a custom service worker registration.
JSPromise<JSString?> _jsGetTokenWithSW(web.ServiceWorkerRegistration swReg, String vapidKey) {
  // We need the compat SDK available in the page. Load it if not already present.
  return _callGetToken(swReg, vapidKey.toJS);
}

@JS('_analfapetGetToken')
external JSPromise<JSString?> _callGetToken(web.ServiceWorkerRegistration swReg, JSString vapidKey);
