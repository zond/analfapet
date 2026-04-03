import 'dart:math';
import 'board.dart';
import 'move.dart';
import 'tile.dart';

class GameState {
  final String gameId;
  final int playerCount;
  final Board board;
  final List<Tile> bag;
  final List<List<Tile>> racks;
  final List<int> scores;
  int turnSeqNr;
  int currentPlayer; // 0-indexed
  int consecutivePasses;
  bool gameOver;
  final SeededPRNG prng;

  GameState({
    required this.gameId,
    required this.playerCount,
    required this.board,
    required this.bag,
    required this.racks,
    required this.scores,
    required this.turnSeqNr,
    required this.currentPlayer,
    this.consecutivePasses = 0,
    this.gameOver = false,
    required this.prng,
  });

  factory GameState.newGame({
    required String gameId,
    required int playerCount,
    required int seed,
  }) {
    final prng = SeededPRNG(seed);
    final bag = Tile.createBag();
    _shuffleBag(bag, prng);

    final racks = <List<Tile>>[];
    for (var p = 0; p < playerCount; p++) {
      final rack = <Tile>[];
      for (var i = 0; i < 7; i++) {
        rack.add(bag.removeLast());
      }
      racks.add(rack);
    }

    return GameState(
      gameId: gameId,
      playerCount: playerCount,
      board: Board(),
      bag: bag,
      racks: racks,
      scores: List.filled(playerCount, 0),
      turnSeqNr: 0,
      currentPlayer: 0,
      prng: prng,
    );
  }

  List<Tile> get currentRack => racks[currentPlayer];

  String get currentPlayerName => 'Player ${currentPlayer + 1}';

  void nextTurn() {
    turnSeqNr++;
    currentPlayer = (currentPlayer + 1) % playerCount;
  }

  void drawTiles(List<Tile> rack, int count) {
    final toDraw = min(count, bag.length);
    for (var i = 0; i < toDraw; i++) {
      rack.add(bag.removeLast());
    }
  }

  /// Apply a move to this game state, mutating it in place.
  void applyMove(Move move) {
    switch (move.type) {
      case MoveType.play:
        for (final p in move.placements) {
          board.set(p.row, p.col, p.placedTile);
          currentRack.remove(p.placedTile.tile);
        }
        scores[currentPlayer] += move.score;
        drawTiles(currentRack, move.placements.length);
        if (currentRack.isEmpty && bag.isEmpty) {
          gameOver = true;
        }
        consecutivePasses = 0;
      case MoveType.pass:
        consecutivePasses++;
      case MoveType.swap:
        if (move.swappedTileLetters != null) {
          final letters = List<String>.from(move.swappedTileLetters!);
          final removed = <Tile>[];
          for (final letter in letters) {
            final idx = currentRack.indexWhere((t) => t.letter == letter);
            if (idx >= 0) {
              removed.add(currentRack.removeAt(idx));
            }
          }
          bag.addAll(removed);
          _shuffleBag(bag, prng);
          drawTiles(currentRack, removed.length);
        }
        consecutivePasses = 0;
      case MoveType.resign:
        gameOver = true;
    }
    if (consecutivePasses >= playerCount * 2) {
      gameOver = true;
    }
    if (!gameOver) {
      nextTurn();
    }
  }

  /// Reconstruct a full GameState by replaying seed + moves.
  static GameState replayFromMoves({
    required String gameId,
    required int playerCount,
    required int seed,
    required List<Move> moves,
  }) {
    final state = GameState.newGame(
      gameId: gameId,
      playerCount: playerCount,
      seed: seed,
    );
    for (final move in moves) {
      state.applyMove(move);
    }
    return state;
  }

  static void _shuffleBag(List<Tile> bag, SeededPRNG prng) {
    for (var i = bag.length - 1; i > 0; i--) {
      final j = prng.nextInt(i + 1);
      final temp = bag[i];
      bag[i] = bag[j];
      bag[j] = temp;
    }
  }
}

/// Deterministic PRNG (xorshift32) so both clients produce identical sequences.
class SeededPRNG {
  int _state;

  SeededPRNG(int seed) : _state = seed == 0 ? 1 : seed;

  int nextInt(int max) {
    // xorshift32
    _state ^= (_state << 13) & 0xFFFFFFFF;
    _state ^= (_state >> 17);
    _state ^= (_state << 5) & 0xFFFFFFFF;
    _state &= 0xFFFFFFFF;
    return (_state.abs()) % max;
  }
}
