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

  String? _playerId;
  String? _secret;
  bool _initialized = false;

  Future<void> init(String playerId, String secret) async {
    _playerId = playerId;
    _secret = secret;
    try {
      // Register service worker early (doesn't need permission)
      final baseHref = web.document.querySelector('base')?.getAttribute('href') ?? '/';
      final swUrl = '${baseHref}firebase-messaging-sw.js';
      print('[FCM] Registering service worker at $swUrl');
      await web.window.navigator.serviceWorker.register(
        swUrl.toJS,
        web.RegistrationOptions(updateViaCache: 'none'),
      ).toDart;
      print('[FCM] Service worker registered');

      // Try to get token if permission already granted (no prompt)
      await _tryGetToken();
    } catch (e) {
      print('[FCM] Init failed (non-fatal): $e');
    }
  }

  /// Request notification permission (should be called from a user gesture on iOS).
  /// Returns true if permission was granted and token was obtained.
  Future<bool> ensurePermission() async {
    if (_initialized) return _token != null;
    try {
      print('[FCM] Requesting permission...');
      final settings = await _messaging.requestPermission();
      print('[FCM] Permission: ${settings.authorizationStatus}');
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        await _tryGetToken();
        return _token != null;
      }
    } catch (e) {
      print('[FCM] Permission request failed: $e');
    }
    return false;
  }

  Future<void> _tryGetToken() async {
    if (_initialized || _playerId == null) return;
    try {
      final swReg = await web.window.navigator.serviceWorker.ready.toDart;
      print('[FCM] Getting token...');
      _token = await _getTokenViaJs(swReg);
      print('[FCM] Token: ${_token != null ? '${_token!.substring(0, 20)}...' : 'null'}');

      if (_token != null) {
        _initialized = true;
        await _registerToken(_playerId!, _token!, _secret!);
        _messaging.onTokenRefresh.listen((token) {
          print('[FCM] Token refreshed');
          _token = token;
          _registerToken(_playerId!, token, _secret!);
        });
      }
    } catch (e) {
      print('[FCM] Token acquisition failed: $e');
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

  /// Fetch all pending messages from the server inbox and clear it.
  Future<List<Map<String, String>>> fetchInbox(String uuid, String secret) async {
    try {
      final resp = await http.post(
        Uri.parse('$_functionsBase/Inbox'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uuid': uuid, 'secret': secret}),
      );
      if (resp.statusCode != 200) {
        print('[FCM] Inbox fetch failed: ${resp.statusCode} ${resp.body}');
        return [];
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final messages = body['messages'] as List?;
      if (messages == null) return [];
      return messages
          .map((m) => (m as Map<String, dynamic>).cast<String, String>())
          .toList();
    } catch (e) {
      print('[FCM] Inbox fetch failed: $e');
      return [];
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
