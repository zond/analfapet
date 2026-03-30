import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/remote_game.dart';

class RemoteGameService {
  static const _key = 'remote_games';

  Future<List<RemoteGame>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => RemoteGame.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveAll(List<RemoteGame> games) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(games.map((g) => g.toJson()).toList()));
  }

  Future<void> save(RemoteGame game) async {
    final games = await loadAll();
    final idx = games.indexWhere((g) => g.gameId == game.gameId);
    if (idx >= 0) {
      games[idx] = game;
    } else {
      games.add(game);
    }
    await _saveAll(games);
  }

  Future<void> delete(String gameId) async {
    final games = await loadAll();
    games.removeWhere((g) => g.gameId == gameId);
    await _saveAll(games);
  }

  Future<RemoteGame?> getById(String gameId) async {
    final games = await loadAll();
    final idx = games.indexWhere((g) => g.gameId == gameId);
    return idx >= 0 ? games[idx] : null;
  }
}
