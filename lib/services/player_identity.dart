import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class PlayerIdentity {
  static const _uuidKey = 'player_uuid';
  static const _nameKey = 'player_name';
  late final String uuid;
  String? _name;

  String? get name => _name;
  bool get hasName => _name != null && _name!.isNotEmpty;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    uuid = prefs.getString(_uuidKey) ?? await _generateUuid(prefs);
    _name = prefs.getString(_nameKey);
  }

  Future<void> setName(String name) async {
    _name = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name);
  }

  Future<String> _generateUuid(SharedPreferences prefs) async {
    final id = const Uuid().v4();
    await prefs.setString(_uuidKey, id);
    return id;
  }
}
