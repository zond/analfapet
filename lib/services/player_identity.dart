import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class PlayerIdentity {
  static const _key = 'player_uuid';
  late final String uuid;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    uuid = prefs.getString(_key) ?? await _generate(prefs);
  }

  Future<String> _generate(SharedPreferences prefs) async {
    final id = const Uuid().v4();
    await prefs.setString(_key, id);
    return id;
  }
}
