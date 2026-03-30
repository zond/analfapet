import 'move.dart';

enum FcmMessageType { invite, accept, deny, move, hurry, stateSync }

class FcmGameMessage {
  final FcmMessageType type;
  final String gameId;
  final String senderId;
  final String senderName;

  // invite fields
  final int? seed;
  final List<String>? playerIds;
  final List<String>? playerNames;

  // move field
  final Move? move;

  // stateSync field
  final List<Move>? moves;

  // hurry field — which player to nudge
  final String? targetId;

  const FcmGameMessage({
    required this.type,
    required this.gameId,
    required this.senderId,
    required this.senderName,
    this.seed,
    this.playerIds,
    this.playerNames,
    this.move,
    this.moves,
    this.targetId,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'gameId': gameId,
        'senderId': senderId,
        'senderName': senderName,
        if (seed != null) 'seed': seed,
        if (playerIds != null) 'playerIds': playerIds,
        if (playerNames != null) 'playerNames': playerNames,
        if (move != null) 'move': move!.toJson(),
        if (moves != null) 'moves': moves!.map((m) => m.toJson()).toList(),
        if (targetId != null) 'targetId': targetId,
      };

  factory FcmGameMessage.fromJson(Map<String, dynamic> json) =>
      FcmGameMessage(
        type: FcmMessageType.values.byName(json['type'] as String),
        gameId: json['gameId'] as String,
        senderId: json['senderId'] as String,
        senderName: json['senderName'] as String,
        seed: json['seed'] as int?,
        playerIds: (json['playerIds'] as List?)?.cast<String>(),
        playerNames: (json['playerNames'] as List?)?.cast<String>(),
        move: json['move'] != null
            ? Move.fromJson(json['move'] as Map<String, dynamic>)
            : null,
        moves: (json['moves'] as List?)
            ?.map((m) => Move.fromJson(m as Map<String, dynamic>))
            .toList(),
        targetId: json['targetId'] as String?,
      );
}
