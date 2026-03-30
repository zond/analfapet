import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

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

      print('[FCM] Getting token...');
      _token = await _messaging.getToken(
        vapidKey: 'BADlJWLuNnXTe6VG4fCEhz-NdXSh5zElySUYFcJoOSRO8Hzs8MDNM_mN1FGb8TJvEZ5T26bKHA_f5irGG74m0tU',
      );
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
              doc.reference.delete();
              return data;
            }).toList());
  }
}
