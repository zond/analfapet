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
      await web.window.navigator.serviceWorker.register(swUrl.toJS).toDart;
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
        final data = _parseData(
          (jsonDecode(jsonStr.toDart) as Map<String, dynamic>),
        );
        handler(data);
      } catch (e) {
        print('[FCM] Failed to parse message: $e');
      }
    }).toJS);
  }

  /// Send data to a single player via Cloud Function.
  Future<void> sendToPlayer(String targetUuid, Map<String, dynamic> data) async {
    print('[FCM] Sending ${data['type']} to $targetUuid...');
    try {
      // Convert all values to strings for FCM data message
      final stringData = <String, String>{};
      for (final entry in data.entries) {
        stringData[entry.key] = entry.value is String
            ? entry.value as String
            : jsonEncode(entry.value);
      }

      final resp = await http.post(
        Uri.parse('$_functionsBase/Send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'targetUuid': targetUuid,
          'data': stringData,
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

  /// Broadcast data to multiple players (excluding self).
  Future<void> broadcast(List<String> playerIds, String myId, Map<String, dynamic> data) async {
    for (final id in playerIds) {
      if (id != myId) {
        await sendToPlayer(id, data);
      }
    }
  }

  /// Parse FCM data message — values arrive as strings, parse JSON where needed.
  Map<String, dynamic> _parseData(Map<String, dynamic> raw) {
    final result = <String, dynamic>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is String) {
        try {
          result[entry.key] = jsonDecode(value);
        } catch (_) {
          result[entry.key] = value;
        }
      } else {
        result[entry.key] = value;
      }
    }
    return result;
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
