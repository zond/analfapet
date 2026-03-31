import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fcm_service.dart';
import 'message_codec.dart';

class Friend {
  final String id;
  final String name;

  const Friend({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Friend.fromJson(Map<String, dynamic> json) =>
      Friend(id: json['id'] as String, name: json['name'] as String);
}

class FriendsService extends ChangeNotifier {
  static final FriendsService instance = FriendsService._();
  static const _key = 'friends';

  FriendsService._();
  factory FriendsService() => instance;

  Future<List<Friend>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => Friend.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> save(List<Friend> friends) async {
    // Deduplicate by UUID (keep first occurrence)
    final seen = <String>{};
    final unique = friends.where((f) => seen.add(f.id)).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(unique.map((f) => f.toJson()).toList()));
  }

  Future<void> add(Friend friend) async {
    final friends = await load();
    if (friends.any((f) => f.id == friend.id)) return;
    friends.add(friend);
    await save(friends);
    notifyListeners();
  }

  Future<void> remove(String id) async {
    final friends = await load();
    friends.removeWhere((f) => f.id == id);
    await save(friends);
    notifyListeners();
  }

  /// Send a friend request via FCM so the other side adds you too.
  Future<void> sendFriendRequest(FcmService fcm, String myId, String myName, String friendId) async {
    final base64Data = MessageCodec.encodeFriendRequest(myId, myName);
    await fcm.sendToPlayer(friendId, base64Data, extra: {'t': 'friend', 'n': myName});
  }
}
