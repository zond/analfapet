import 'move.dart';

enum RemoteGameStatus { invited, accepted, active, finished }

class RemotePlayer {
  final String uuid;
  final String name;
  bool accepted;

  RemotePlayer({required this.uuid, required this.name, this.accepted = false});

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'name': name,
        'accepted': accepted,
      };

  factory RemotePlayer.fromJson(Map<String, dynamic> json) => RemotePlayer(
        uuid: json['uuid'] as String,
        name: json['name'] as String,
        accepted: json['accepted'] as bool? ?? false,
      );
}

class RemoteGame {
  final String gameId;
  final int seed;
  final List<RemotePlayer> players;
  final String creatorId;
  RemoteGameStatus status;
  final List<Move> moves;
  final DateTime createdAt;
  DateTime updatedAt;

  RemoteGame({
    required this.gameId,
    required this.seed,
    required this.players,
    required this.creatorId,
    required this.status,
    List<Move>? moves,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : moves = moves ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get allAccepted => players.every((p) => p.accepted);

  int playerIndex(String uuid) => players.indexWhere((p) => p.uuid == uuid);

  Map<String, dynamic> toJson() => {
        'gameId': gameId,
        'seed': seed,
        'players': players.map((p) => p.toJson()).toList(),
        'creatorId': creatorId,
        'status': status.name,
        'moves': moves.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory RemoteGame.fromJson(Map<String, dynamic> json) => RemoteGame(
        gameId: json['gameId'] as String,
        seed: json['seed'] as int,
        players: (json['players'] as List)
            .map((p) => RemotePlayer.fromJson(p as Map<String, dynamic>))
            .toList(),
        creatorId: json['creatorId'] as String,
        status: RemoteGameStatus.values.byName(json['status'] as String),
        moves: (json['moves'] as List?)
                ?.map((m) => Move.fromJson(m as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}
