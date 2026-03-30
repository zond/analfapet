import 'dart:convert';
import 'dart:js_interop';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

const _vapidKey = 'BADlJWLuNnXTe6VG4fCEhz-NdXSh5zElySUYFcJoOSRO8Hzs8MDNM_mN1FGb8TJvEZ5T26bKHA_f5irGG74m0tU';
const _functionsBase = 'https://europe-west1-fcm-switch.cloudfunctions.net';

class FcmService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  String? _token;

  String? get token => _token;

  Future<void> init(String playerId, String secret) async {
    try {
      print('[FCM] Requesting permission...');
      final settings = await _messaging.requestPermission();
      print('[FCM] Permission: ${settings.authorizationStatus}');

      // Register service worker at correct path for subpath deploys
      final baseHref = web.document.querySelector('base')?.getAttribute('href') ?? '/';
      final swUrl = '${baseHref}firebase-messaging-sw.js';
      print('[FCM] Registering service worker at $swUrl');
      await web.window.navigator.serviceWorker.register(
        swUrl.toJS,
        web.RegistrationOptions(updateViaCache: 'none'),
      ).toDart;
      print('[FCM] Service worker registered, waiting for ready...');
      final swReg = await web.window.navigator.serviceWorker.ready.toDart;
      print('[FCM] Service worker ready');

      print('[FCM] Getting token...');
      _token = await _getTokenViaJs(swReg);
      print('[FCM] Token: ${_token != null ? '${_token!.substring(0, 20)}...' : 'null'}');

      if (_token != null) {
        await _registerToken(playerId, _token!, secret);
      }
      _messaging.onTokenRefresh.listen((token) {
        print('[FCM] Token refreshed');
        _token = token;
        _registerToken(playerId, token, secret);
      });
    } catch (e) {
      print('[FCM] Init failed (non-fatal): $e');
    }
  }

  Future<String?> _getTokenViaJs(web.ServiceWorkerRegistration swReg) async {
    final result = await _jsGetTokenWithSW(swReg, _vapidKey).toDart;
    return result?.toDart;
  }

  Future<void> _registerToken(String playerId, String token, String secret) async {
    print('[FCM] Registering token via Cloud Function...');
    try {
      final resp = await http.post(
        Uri.parse('$_functionsBase/Register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uuid': playerId,
          'token': token,
          'secret': secret,
        }),
      );
      if (resp.statusCode == 200) {
        print('[FCM] Token registered');
      } else {
        print('[FCM] Registration failed: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      print('[FCM] Registration failed: $e');
    }
  }

  void onMessageHandler(void Function(Map<String, dynamic> data) handler) {
    // Use compat SDK's onMessage via JS callback (same instance as getToken)
    _setOnMessageCallback(((JSString jsonStr) {
      print('[FCM] Message received via compat SDK');
      try {
        final data = (jsonDecode(jsonStr.toDart) as Map<String, dynamic>);
        handler(data);
      } catch (e) {
        print('[FCM] Failed to parse message: $e');
      }
    }).toJS);
  }

  /// Send a binary-encoded message to a single player via Cloud Function.
  /// [base64Data] is the base64-encoded binary payload.
  /// [extra] contains optional human-readable fields for service worker notifications
  /// (e.g. 't' for type, 'n' for sender name).
  Future<void> sendToPlayer(String targetUuid, String base64Data, {Map<String, String>? extra}) async {
    print('[FCM] Sending to $targetUuid...');
    try {
      final data = <String, String>{'d': base64Data};
      if (extra != null) data.addAll(extra);

      final resp = await http.post(
        Uri.parse('$_functionsBase/Send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'targetUuid': targetUuid,
          'data': data,
        }),
      );
      if (resp.statusCode == 200) {
        print('[FCM] Send OK');
      } else {
        print('[FCM] Send failed: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      print('[FCM] Send failed: $e');
    }
  }

  /// Broadcast a binary-encoded message to multiple players (excluding self).
  Future<void> broadcast(List<String> playerIds, String myId, String base64Data, {Map<String, String>? extra}) async {
    for (final id in playerIds) {
      if (id != myId) {
        await sendToPlayer(id, base64Data, extra: extra);
      }
    }
  }
}

JSPromise<JSString?> _jsGetTokenWithSW(web.ServiceWorkerRegistration swReg, String vapidKey) {
  return _callGetToken(swReg, vapidKey.toJS);
}

@JS('_analfapetGetToken')
external JSPromise<JSString?> _callGetToken(web.ServiceWorkerRegistration swReg, JSString vapidKey);

void _setOnMessageCallback(JSFunction callback) {
  _analfapetSetOnMessage(callback);
}

@JS()
external set _analfapetOnMessage(JSFunction? callback);

void _analfapetSetOnMessage(JSFunction callback) {
  _analfapetOnMessage = callback;
}
