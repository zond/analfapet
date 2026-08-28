import 'dart:convert';
import 'dart:js_interop';
import 'package:http/http.dart' as http;

const _functionsBase = 'https://europe-west1-fcm-switch.cloudfunctions.net';

@JS('_analfapetGoogleSignIn')
external JSPromise<JSString> _jsGoogleSignIn();

/// Admin-only helpers (server enforces a Google account allowlist).
class AdminService {
  /// Trigger a Google sign-in popup; returns a Firebase ID token.
  static Future<String> googleSignIn() async =>
      (await _jsGoogleSignIn().toDart).toDart;

  /// Fetch the stored secret for [uuid] so the identity can be re-assumed.
  /// Throws on any failure (bad token, not allowlisted, unknown player).
  static Future<String> recoverSecret(String uuid, String idToken) async {
    final resp = await http.post(
      Uri.parse('$_functionsBase/Recover'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'uuid': uuid, 'idToken': idToken}),
    );
    if (resp.statusCode != 200) {
      throw Exception('Recover failed: ${resp.statusCode} ${resp.body}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return body['secret'] as String;
  }
}
