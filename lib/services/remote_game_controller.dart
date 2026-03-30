import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/fcm_message.dart';
import '../models/game_state.dart';
import '../models/move.dart';
import '../models/remote_game.dart';
import 'fcm_service.dart';
import 'friends_service.dart';
import 'player_identity.dart';
import 'remote_game_service.dart';

class RemoteGameController extends ChangeNotifier {
  final FcmService fcm;
  final RemoteGameService storage;
  final String myId;
  final PlayerIdentity identity;

  String get myName => identity.name ?? 'Anonymous';

  List<RemoteGame> _games = [];
  List<RemoteGame> get games => _games;

  List<RemoteGame> get invitations =>
      _games.where((g) => g.status == RemoteGameStatus.invited).toList();
  List<RemoteGame> get activeGames =>
      _games.where((g) => g.status == RemoteGameStatus.active).toList();
  List<RemoteGame> get finishedGames =>
      _games.where((g) => g.status == RemoteGameStatus.finished).toList();

  RemoteGameController({
    required this.fcm,
    required this.storage,
    required this.myId,
    required this.identity,
  });

  Future<void> load() async {
    _games = await storage.loadAll();
    notifyListeners();
  }

  Future<void> _save(RemoteGame game) async {
    game.updatedAt = DateTime.now();
    await storage.save(game);
    await load();
  }

  // --- Outbound ---

  Future<RemoteGame> createGame(List<Friend> friends) async {
    final gameId = const Uuid().v4();
    final seed = Random().nextInt(0xFFFFFFFF);

    final players = <RemotePlayer>[
      RemotePlayer(uuid: myId, name: myName, accepted: true),
      ...friends.map((f) => RemotePlayer(uuid: f.id, name: f.name)),
    ];

    final game = RemoteGame(
      gameId: gameId,
      seed: seed,
      players: players,
      creatorId: myId,
      status: RemoteGameStatus.active, // creator is auto-accepted, waiting for others
    );

    // If only 2 players and creator is auto-accepted, check if game can start
    if (!game.allAccepted) {
      game.status = RemoteGameStatus.active; // waiting for acceptances
    }

    await _save(game);

    final msg = FcmGameMessage(
      type: FcmMessageType.invite,
      gameId: gameId,
      senderId: myId,
      senderName: myName,
      seed: seed,
      playerIds: players.map((p) => p.uuid).toList(),
      playerNames: players.map((p) => p.name).toList(),
    );

    await fcm.broadcast(
      players.map((p) => p.uuid).toList(),
      myId,
      msg.toJson(),
    );

    return game;
  }

  Future<void> acceptInvite(String gameId) async {
    final game = _games.firstWhere((g) => g.gameId == gameId);
    final me = game.players.firstWhere((p) => p.uuid == myId);
    me.accepted = true;
    game.status = RemoteGameStatus.accepted;
    if (game.allAccepted) {
      game.status = RemoteGameStatus.active;
    }
    await _save(game);

    final msg = FcmGameMessage(
      type: FcmMessageType.accept,
      gameId: gameId,
      senderId: myId,
      senderName: myName,
    );
    await fcm.broadcast(
      game.players.map((p) => p.uuid).toList(),
      myId,
      msg.toJson(),
    );
  }

  Future<void> denyInvite(String gameId) async {
    final game = _games.firstWhere((g) => g.gameId == gameId);

    final msg = FcmGameMessage(
      type: FcmMessageType.deny,
      gameId: gameId,
      senderId: myId,
      senderName: myName,
    );
    await fcm.broadcast(
      game.players.map((p) => p.uuid).toList(),
      myId,
      msg.toJson(),
    );

    await deleteGame(gameId);
  }

  Future<void> sendMove(String gameId, Move move) async {
    final game = _games.firstWhere((g) => g.gameId == gameId);
    game.moves.add(move);
    await _save(game);

    final msg = FcmGameMessage(
      type: FcmMessageType.move,
      gameId: gameId,
      senderId: myId,
      senderName: myName,
      move: move,
    );
    await fcm.broadcast(
      game.players.map((p) => p.uuid).toList(),
      myId,
      msg.toJson(),
    );
  }

  Future<void> sendHurry(String gameId, String targetId) async {
    final msg = FcmGameMessage(
      type: FcmMessageType.hurry,
      gameId: gameId,
      senderId: myId,
      senderName: myName,
      targetId: targetId,
    );
    await fcm.sendToPlayer(targetId, msg.toJson());
  }

  Future<void> sendStateSync(String gameId) async {
    final game = _games.firstWhere((g) => g.gameId == gameId);
    final msg = FcmGameMessage(
      type: FcmMessageType.stateSync,
      gameId: gameId,
      senderId: myId,
      senderName: myName,
      moves: game.moves,
    );
    await fcm.broadcast(
      game.players.map((p) => p.uuid).toList(),
      myId,
      msg.toJson(),
    );
  }

  Future<void> deleteGame(String gameId) async {
    await storage.delete(gameId);
    await load();
  }

  // --- Inbound ---

  /// Returns a toast message, or null to suppress the toast.
  Future<String?> handleMessage(Map<String, dynamic> data) async {
    final msg = FcmGameMessage.fromJson(data);
    final sender = msg.senderName;
    switch (msg.type) {
      case FcmMessageType.invite:
        await _handleInvite(msg);
        return '$sender invites you to a game';
      case FcmMessageType.accept:
        await _handleAccept(msg);
        return '$sender accepted the invite';
      case FcmMessageType.deny:
        await _handleDeny(msg);
        return '$sender declined the invite';
      case FcmMessageType.move:
        await _handleMove(msg);
        return '$sender played a move';
      case FcmMessageType.hurry:
        return await _handleHurry(msg);
      case FcmMessageType.stateSync:
        await _handleStateSync(msg);
        return null; // silent
    }
  }

  Future<void> _handleInvite(FcmGameMessage msg) async {
    // Don't create duplicate
    if (_games.any((g) => g.gameId == msg.gameId)) return;

    final players = <RemotePlayer>[];
    for (var i = 0; i < msg.playerIds!.length; i++) {
      players.add(RemotePlayer(
        uuid: msg.playerIds![i],
        name: msg.playerNames![i],
        accepted: msg.playerIds![i] == msg.senderId, // creator is accepted
      ));
    }

    final game = RemoteGame(
      gameId: msg.gameId,
      seed: msg.seed!,
      players: players,
      creatorId: msg.senderId,
      status: RemoteGameStatus.invited,
    );
    await _save(game);
  }

  Future<void> _handleAccept(FcmGameMessage msg) async {
    final game = _games.cast<RemoteGame?>().firstWhere(
          (g) => g!.gameId == msg.gameId,
          orElse: () => null,
        );
    if (game == null) return;

    final player = game.players.cast<RemotePlayer?>().firstWhere(
          (p) => p!.uuid == msg.senderId,
          orElse: () => null,
        );
    if (player != null) player.accepted = true;

    if (game.allAccepted) {
      game.status = RemoteGameStatus.active;
    }
    await _save(game);
  }

  Future<void> _handleDeny(FcmGameMessage msg) async {
    final game = _games.cast<RemoteGame?>().firstWhere(
          (g) => g!.gameId == msg.gameId,
          orElse: () => null,
        );
    if (game == null) return;

    // Mark game as finished (cancelled)
    game.status = RemoteGameStatus.finished;
    await _save(game);
  }

  Future<void> _handleMove(FcmGameMessage msg) async {
    final game = _games.cast<RemoteGame?>().firstWhere(
          (g) => g!.gameId == msg.gameId,
          orElse: () => null,
        );
    if (game == null) return;

    final move = msg.move!;
    // Only append if it's the next expected move
    if (move.turnSeqNr == game.moves.length) {
      game.moves.add(move);
      await _save(game);
    } else if (move.turnSeqNr > game.moves.length) {
      // We missed moves — request sync
      await fcm.sendToPlayer(
        msg.senderId,
        FcmGameMessage(
          type: FcmMessageType.hurry,
          gameId: msg.gameId,
          senderId: myId,
          senderName: myName,
          targetId: msg.senderId,
        ).toJson(),
      );
    }
    // If behind, ignore (duplicate)
  }

  Future<String?> _handleHurry(FcmGameMessage msg) async {
    final game = _games.cast<RemoteGame?>().firstWhere(
          (g) => g!.gameId == msg.gameId,
          orElse: () => null,
        );
    if (game == null) return null;

    // Always send our state so they can catch up if needed
    await sendStateSync(msg.gameId);

    // Check if it's actually our turn — if so, the hurry is legitimate
    final state = GameState.replayFromMoves(
      gameId: game.gameId,
      playerCount: game.players.length,
      seed: game.seed,
      moves: game.moves,
    );
    final myIndex = game.playerIndex(myId);
    if (state.currentPlayer == myIndex) {
      return '${msg.senderName} asks you to hurry up!';
    } else {
      // They had stale state — we sent an update, no need to nag the user
      return '${msg.senderName} had an old game state, sent update';
    }
  }

  Future<void> _handleStateSync(FcmGameMessage msg) async {
    final game = _games.cast<RemoteGame?>().firstWhere(
          (g) => g!.gameId == msg.gameId,
          orElse: () => null,
        );
    if (game == null) return;

    // Accept if incoming has more moves
    if (msg.moves != null && msg.moves!.length > game.moves.length) {
      game.moves.clear();
      game.moves.addAll(msg.moves!);
      await _save(game);
    }
  }
}
