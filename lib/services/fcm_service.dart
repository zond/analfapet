import 'dart:convert';
import 'dart:js_interop';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:web/web.dart' as web;

class FcmService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> init(String playerId) async {
    // Register service worker with correct relative path (needed for GitHub Pages subpath)
    try {
      final baseHref = web.document.querySelector('base')?.getAttribute('href') ?? '/';
      final swUrl = '${baseHref}firebase-messaging-sw.js';
      print('[FCM] Registering service worker at $swUrl');
      await web.window.navigator.serviceWorker.register(swUrl.toJS).toDart;
      print('[FCM] Service worker registered');
    } catch (e) {
      print('[FCM] Service worker registration failed: $e');
    }

    print('[FCM] Requesting permission...');
    final settings = await _messaging.requestPermission();
    print('[FCM] Permission: ${settings.authorizationStatus}');

    print('[FCM] Getting token...');
    final token = await _messaging.getToken(
      vapidKey: 'BADlJWLuNnXTe6VG4fCEhz-NdXSh5zElySUYFcJoOSRO8Hzs8MDNM_mN1FGb8TJvEZ5T26bKHA_f5irGG74m0tU',
    );
    print('[FCM] Token: ${token != null ? '${token.substring(0, 20)}...' : 'null'}');

    if (token != null) {
      await _registerToken(playerId, token);
    }
    _messaging.onTokenRefresh.listen((token) {
      print('[FCM] Token refreshed');
      _registerToken(playerId, token);
    });
  }

  Future<void> _registerToken(String playerId, String token) async {
    print('[FCM] Registering token for player $playerId...');
    await _firestore.collection('players').doc(playerId).set({
      'fcmToken': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    print('[FCM] Token registered in Firestore');
  }

  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

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

  /// Send a move via FCM. In production this would go through a minimal
  /// Cloud Function or use the FCM HTTP v1 API from the client with
  /// a service account. For now we store moves in Firestore as a relay.
  Future<void> sendMove(String targetPlayerId, Map<String, dynamic> moveData) async {
    await _firestore
        .collection('players')
        .doc(targetPlayerId)
        .collection('inbox')
        .add({
      'data': jsonEncode(moveData),
      'timestamp': FieldValue.serverTimestamp(),
    });
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
              // Delete after reading
              doc.reference.delete();
              return data;
            }).toList());
  }
}
