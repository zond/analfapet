import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class PlayerIdentity {
  static const _uuidKey = 'player_uuid';
  static const _nameKey = 'player_name';
  static const _secretKey = 'player_secret';
  late final String uuid;
  late final String secret;
  String? _name;

  String? get name => _name;
  bool get hasName => _name != null && _name!.isNotEmpty;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    uuid = prefs.getString(_uuidKey) ?? await _generate(prefs, _uuidKey);
    secret = prefs.getString(_secretKey) ?? await _generate(prefs, _secretKey);
    _name = prefs.getString(_nameKey);
  }

  /// Re-read name from storage (in case it was set in another context).
  Future<void> refreshName() async {
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString(_nameKey);
  }

  Future<void> setName(String name) async {
    _name = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name);
  }

  Future<String> _generate(SharedPreferences prefs, String key) async {
    final id = const Uuid().v4();
    await prefs.setString(key, id);
    return id;
  }
}
