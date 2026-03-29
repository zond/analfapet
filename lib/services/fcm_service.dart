import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class FcmService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> init(String playerId) async {
    await _messaging.requestPermission();
    final token = await _messaging.getToken();
    if (token != null) {
      await _registerToken(playerId, token);
    }
    _messaging.onTokenRefresh.listen((token) => _registerToken(playerId, token));
  }

  Future<void> _registerToken(String playerId, String token) async {
    await _firestore.collection('players').doc(playerId).set({
      'fcmToken': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  void onMessageHandler(void Function(Map<String, dynamic> data) handler) {
    FirebaseMessaging.onMessage.listen((message) {
      if (message.data.isNotEmpty) {
        handler(message.data);
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
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
