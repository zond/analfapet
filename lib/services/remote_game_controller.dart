import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/game_state.dart';
import '../models/move.dart';
import '../models/remote_game.dart';
import 'dictionary.dart';
import 'fcm_service.dart';
import 'friends_service.dart';
import 'message_codec.dart';
import 'move_validator.dart';
import 'player_identity.dart';
import 'remote_game_service.dart';

class RemoteGameController extends ChangeNotifier {
  final FcmService fcm;
  final RemoteGameService storage;
  final String myId;
  final PlayerIdentity identity;
  final Dictionary dictionary;
  late final MoveValidator _validator;

  String get myName => identity.name ?? 'Anonymous';

  List<RemoteGame> _games = [];
  List<RemoteGame> get games => _games;

  List<RemoteGame> get invitations =>
      _games.where((g) => g.status == RemoteGameStatus.invited).toList();
  List<RemoteGame> get activeGames =>
      _games.where((g) => g.status == RemoteGameStatus.active || g.status == RemoteGameStatus.accepted).toList();
  List<RemoteGame> get finishedGames =>
      _games.where((g) => g.status == RemoteGameStatus.finished).toList();

  /// The game ID currently being viewed by the user (set by RemoteGameScreen).
  String? currentViewingGameId;

  /// Check if an active game is actually finished via gameplay (game over).
  bool isGameOverViaGameplay(RemoteGame game) {
    if (game.status != RemoteGameStatus.active) return false;
    if (game.moves.isEmpty) return false;
    final state = GameState.replayFromMoves(
      gameId: game.gameId,
      playerCount: game.players.length,
      seed: game.seed,
      moves: game.moves,
    );
    return state.gameOver;
  }

  RemoteGameController({
    required this.fcm,
    required this.storage,
    required this.myId,
    required this.identity,
    required this.dictionary,
  }) {
    _validator = MoveValidator(dictionary);
  }

  Future<void> load() async {
    _games = await storage.loadAll();
    notifyListeners();
  }

  /// Get accepted players sorted by UUID (the canonical game order).
  List<RemotePlayer> _sortedAccepted(RemoteGame game) {
    final accepted = game.players.where((p) => p.accepted).toList();
    accepted.sort((a, b) => a.uuid.compareTo(b.uuid));
    return accepted;
  }

  /// Finalize the game: keep only accepted players, sort by UUID, activate.
  /// Idempotent — safe to call multiple times.
  void _finalizeGame(RemoteGame game) {
    final sorted = _sortedAccepted(game);
    game.players
      ..clear()
      ..addAll(sorted);
    game.status = RemoteGameStatus.active;
  }

  Future<void> _save(RemoteGame game) async {
    game.updatedAt = DateTime.now();
    await storage.save(game);
    await load();
  }

  // --- Serialized message handling (Fix #18) ---

  Future<void> _pending = Future.value();

  /// Wrap handleGameMessage so concurrent calls are serialized.
  Future<String?> handleGameMessage(Map<String, dynamic> decoded) {
    final result = _pending.then((_) => _handleGameMessageImpl(decoded));
    _pending = result.then((_) {}, onError: (_) {});
    return result;
  }

  // --- Outbound ---

  /// Encode the current game state and broadcast to all players.
  Future<void> sendGameState(String gameId) async {
    final game = _games.firstWhere((g) => g.gameId == gameId);
    final base64Data = MessageCodec.encodeGameState(game);
    final notifType = MessageCodec.notificationType(game);

    // Include whose turn it is for notification text
    String? turnName;
    if (game.status == RemoteGameStatus.active) {
      if (game.moves.isNotEmpty) {
        final state = GameState.replayFromMoves(
          gameId: game.gameId,
          playerCount: game.players.length,
          seed: game.seed,
          moves: game.moves,
        );
        if (!state.gameOver) {
          turnName = game.players[state.currentPlayer].name;
        }
      } else if (game.players.isNotEmpty) {
        // Zero moves — player 0 goes first
        turnName = game.players[0].name;
      }
    }

    // Determine the action label for the last move (for background notifications)
    String? action;
    if (game.moves.isNotEmpty) {
      switch (game.moves.last.type) {
        case MoveType.play:
          action = 'played';
          break;
        case MoveType.pass:
          action = 'passed';
          break;
        case MoveType.swap:
          action = 'swapped';
          break;
        case MoveType.resign:
          action = 'resigned';
          break;
      }
    }

    await fcm.broadcast(
      game.players.map((p) => p.uuid).toList(),
      myId,
      base64Data,
      extra: {
        't': notifType,
        'n': myName,
        'g': gameId,
        if (turnName != null) 'turn': turnName,
        if (action != null) 'a': action,
      },
    );
  }

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
      status: RemoteGameStatus.accepted, // waiting for other players to accept
    );

    if (game.allAccepted) {
      _finalizeGame(game);
    }

    await _save(game);
    await sendGameState(gameId);

    return game;
  }

  Future<void> acceptInvite(String gameId) async {
    final game = _games.firstWhere((g) => g.gameId == gameId);
    final me = game.players.firstWhere((p) => p.uuid == myId);
    me.accepted = true;
    game.status = RemoteGameStatus.accepted;
    if (game.allAccepted) {
      _finalizeGame(game);
    }
    await _save(game);
    await sendGameState(gameId);
  }

  Future<void> denyInvite(String gameId) async {
    final game = _games.firstWhere((g) => g.gameId == gameId);
    // Mark self as denied
    final me = game.players.firstWhere((p) => p.uuid == myId);
    me.denied = true;
    me.accepted = false;
    await sendGameState(gameId);
    await deleteGame(gameId);
  }

  Future<void> sendMove(String gameId, Move move) async {
    final game = _games.firstWhere((g) => g.gameId == gameId);
    game.moves.add(move);
    await _save(game);
    await sendGameState(gameId);
  }

  Future<void> deleteGame(String gameId) async {
    await storage.delete(gameId);
    await load();
  }

  // --- Inbound ---

  /// Handle an incoming decoded message (implementation).
  /// Returns a toast message, or null to suppress the toast.
  Future<String?> _handleGameMessageImpl(Map<String, dynamic> decoded) async {
    final gameId = decoded['gameId'] as String;
    final seed = decoded['seed'] as int;
    final playersData = decoded['players'] as List<Map<String, dynamic>>;
    final incomingMoves = decoded['moves'] as List<Move>;

    // Build incoming player list
    final incomingPlayers = playersData.map((p) => RemotePlayer(
      uuid: p['uuid'] as String,
      name: p['name'] as String,
      accepted: (p['status'] as int) == 1,
      denied: (p['status'] as int) == 2,
    )).toList();

    // Find the sender: the first player whose status differs from what we know,
    // or just pick the first non-self player as a reasonable guess for toast messages.
    String senderName = 'Someone';

    final existingGame = _games.cast<RemoteGame?>().firstWhere(
      (g) => g!.gameId == gameId,
      orElse: () => null,
    );

    if (existingGame == null) {
      // New game — this is an invite
      // The creator is the accepted player (who isn't us)
      final creator = incomingPlayers.firstWhere(
        (p) => p.accepted && p.uuid != myId,
        orElse: () => incomingPlayers.firstWhere((p) => p.uuid != myId),
      );
      senderName = creator.name;

      final game = RemoteGame(
        gameId: gameId,
        seed: seed,
        players: incomingPlayers,
        creatorId: creator.uuid,
        status: RemoteGameStatus.invited,
      );

      // Fix #8: If all accepted already, finalize before saving
      if (game.allAccepted) {
        _finalizeGame(game);
      }

      await _save(game);
      return '$senderName invites you to a game';
    }

    // Game exists — merge state
    final game = existingGame;

    // Track whether anything actually changed (Fix #15)
    bool anythingChanged = false;
    final wasActive = game.status == RemoteGameStatus.active;

    // If incoming has all-accepted players and game isn't active yet,
    // adopt their list (sorted by UUID from finalization).
    // Never modify the player list of an active game — it would corrupt move replay.
    final allIncomingAccepted = incomingPlayers.every((p) => p.accepted || p.denied);
    if (allIncomingAccepted && incomingPlayers.length >= 2 && game.status != RemoteGameStatus.active) {
      // Check if player list differs from ours
      final incomingUuids = incomingPlayers.where((p) => p.accepted).map((p) => p.uuid).toList();
      final localUuids = game.players.map((p) => p.uuid).toList();
      if (incomingUuids.join(',') != localUuids.join(',')) {
        // Adopt the incoming player list
        game.players
          ..clear()
          ..addAll(incomingPlayers.where((p) => p.accepted));
        game.players.sort((a, b) => a.uuid.compareTo(b.uuid));
        game.status = RemoteGameStatus.active;
        anythingChanged = true;
      }
    }

    // Update player statuses from incoming
    for (final incoming in incomingPlayers) {
      final local = game.players.cast<RemotePlayer?>().firstWhere(
        (p) => p!.uuid == incoming.uuid,
        orElse: () => null,
      );
      if (local != null) {
        if (incoming.denied) {
          if (!local.denied) anythingChanged = true;
          local.denied = true;
          local.accepted = false;
        } else if (incoming.accepted && !local.accepted) {
          anythingChanged = true;
          local.accepted = true;
        }
      }
    }

    // Determine sender by finding what changed (after player list adoption/status merge)
    senderName = _findSender(game, incomingPlayers, incomingMoves);

    // Handle denied players: remove them (skip if game is active)
    final deniedPlayers = game.players.where((p) => p.denied).toList();
    if (game.status != RemoteGameStatus.active) {
      for (final denied in deniedPlayers) {
        game.players.removeWhere((p) => p.uuid == denied.uuid);
      }

      if (game.players.length <= 1) {
        game.status = RemoteGameStatus.finished;
        await _save(game);
        if (deniedPlayers.isNotEmpty) {
          return '${deniedPlayers.first.name} declined the invite';
        }
        return 'Game cancelled';
      }
    }

    // Check if all remaining players have accepted
    if (game.allAccepted && game.status != RemoteGameStatus.active) {
      _finalizeGame(game);
      anythingChanged = true;
    }

    // Merge moves: accept if incoming has more and they validate
    // Fix #7: Only merge moves if game is active
    bool movesMerged = false;
    bool movesRejected = false;
    if (game.status == RemoteGameStatus.active && incomingMoves.length > game.moves.length) {
      // Verify our existing moves are a prefix of the incoming moves
      bool prefixMatch = true;
      for (var i = 0; i < game.moves.length; i++) {
        if (game.moves[i].turnSeqNr != incomingMoves[i].turnSeqNr) {
          prefixMatch = false;
          break;
        }
      }

      if (prefixMatch) {
        // Validate each new move beyond what we already have
        final tempGame = RemoteGame(
          gameId: game.gameId,
          seed: game.seed,
          players: List.of(game.players),
          creatorId: game.creatorId,
          status: game.status,
          moves: List.of(game.moves),
        );
        bool allValid = true;
        for (var i = game.moves.length; i < incomingMoves.length; i++) {
          final error = _validateMove(tempGame, incomingMoves[i]);
          if (error != null) {
            print('[Game] Rejected incoming move $i: $error');
            allValid = false;
            break;
          }
          tempGame.moves.add(incomingMoves[i]);
        }

        if (allValid) {
          game.moves.clear();
          game.moves.addAll(incomingMoves);
          movesMerged = true;
          anythingChanged = true;
        } else {
          movesRejected = true;
        }
      } else {
        movesRejected = true;
      }
    }

    await _save(game);

    // Fix #3: Auto-reply with current state when we have more moves
    if (game.status == RemoteGameStatus.active && incomingMoves.length < game.moves.length) {
      await sendGameState(gameId);
    }

    // If nothing changed, no toast (background notification handles nudges)
    if (!anythingChanged && !movesRejected) {
      return null;
    }

    // Fix #9: Toast for rejected moves
    if (movesRejected) {
      return 'Invalid game state received from $senderName';
    }

    // Generate appropriate toast
    if (deniedPlayers.isNotEmpty && game.status != RemoteGameStatus.active) {
      return '${deniedPlayers.first.name} declined the invite';
    }
    if (movesMerged) {
      // Determine whose turn it is now
      final state = GameState.replayFromMoves(
        gameId: game.gameId,
        playerCount: game.players.length,
        seed: game.seed,
        moves: game.moves,
      );
      if (state.gameOver) {
        return 'Game over!';
      }
      final currentPlayer = game.players[state.currentPlayer];
      final turnName = currentPlayer.uuid == myId ? 'Your' : "${currentPlayer.name}'s";
      final lastMoveType = game.moves.last.type;
      switch (lastMoveType) {
        case MoveType.play:
          return '$senderName played — $turnName turn';
        case MoveType.pass:
          return '$senderName passed — $turnName turn';
        case MoveType.swap:
          return '$senderName swapped tiles — $turnName turn';
        case MoveType.resign:
          return '$senderName resigned';
      }
    }
    if (game.status == RemoteGameStatus.active && !wasActive) {
      return '$senderName accepted the invite';
    }
    return 'Game updated from $senderName';
  }

  /// Try to identify who sent this update by looking at what changed.
  String _findSender(RemoteGame localGame, List<RemotePlayer> incomingPlayers, List<Move> incomingMoves) {
    // If there are more moves in incoming, the "sender" is the player whose turn it was
    if (incomingMoves.length > localGame.moves.length && localGame.players.isNotEmpty) {
      final playerCount = localGame.players.length;
      if (playerCount > 0) {
        final lastMoveIndex = incomingMoves.length - 1;
        final playerIndex = lastMoveIndex % playerCount;
        if (playerIndex < localGame.players.length) {
          final player = localGame.players[playerIndex];
          if (player.uuid != myId) return player.name;
        }
      }
    }

    // Check for newly accepted players
    for (final incoming in incomingPlayers) {
      if (incoming.uuid == myId) continue;
      final local = localGame.players.cast<RemotePlayer?>().firstWhere(
        (p) => p!.uuid == incoming.uuid,
        orElse: () => null,
      );
      if (local != null && !local.accepted && incoming.accepted) {
        return incoming.name;
      }
      if (local != null && !local.denied && incoming.denied) {
        return incoming.name;
      }
    }

    // Default: first non-self player
    for (final p in incomingPlayers) {
      if (p.uuid != myId) return p.name;
    }
    return 'Someone';
  }

  /// Validate a move against the current game state.
  /// Returns null if valid, or an error string if invalid.
  String? _validateMove(RemoteGame game, Move move) {
    final state = GameState.replayFromMoves(
      gameId: game.gameId,
      playerCount: game.players.length,
      seed: game.seed,
      moves: game.moves,
    );

    // Validate play moves against dictionary and rules
    if (move.type == MoveType.play) {
      final isFirstMove = state.board.isEmptyBoard;
      final result = _validator.validate(state.board, move.placements, isFirstMove);
      if (!result.valid) {
        return result.error;
      }
      // Fix #2: Validate score matches computed score
      if (move.score != result.score) {
        return 'Score mismatch';
      }
    }

    // Fix #12: Validate swap moves — check that swapped tile letters exist in rack
    if (move.type == MoveType.swap) {
      final rack = List<String>.from(state.racks[state.currentPlayer].map((t) => t.letter));
      for (final letter in (move.swappedTileLetters ?? <String>[])) {
        final idx = rack.indexOf(letter);
        if (idx < 0) {
          return 'Swap contains tile not in rack: $letter';
        }
        rack.removeAt(idx);
      }
    }

    // Pass and resign: no additional validation needed.

    return null;
  }
}
