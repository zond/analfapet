import 'dart:math';
import 'board.dart';
import 'tile.dart';

class GameState {
  final String gameId;
  final String localPlayerId;
  final String remotePlayerId;
  final Board board;
  final List<Tile> bag;
  final List<Tile> localRack;
  final List<Tile> remoteRack;
  final List<int> scores; // [local, remote]
  int turnSeqNr;
  bool localPlayerTurn;
  int consecutivePasses;
  bool gameOver;
  final SeededPRNG prng;

  GameState({
    required this.gameId,
    required this.localPlayerId,
    required this.remotePlayerId,
    required this.board,
    required this.bag,
    required this.localRack,
    required this.remoteRack,
    required this.scores,
    required this.turnSeqNr,
    required this.localPlayerTurn,
    this.consecutivePasses = 0,
    this.gameOver = false,
    required this.prng,
  });

  factory GameState.newGame({
    required String gameId,
    required String localPlayerId,
    required String remotePlayerId,
    required int seed,
    required bool localGoesFirst,
  }) {
    final prng = SeededPRNG(seed);
    final bag = Tile.createBag();
    _shuffleBag(bag, prng);

    final localRack = <Tile>[];
    final remoteRack = <Tile>[];

    // Draw 7 tiles each; first player draws first
    if (localGoesFirst) {
      for (var i = 0; i < 7; i++) {
        localRack.add(bag.removeLast());
      }
      for (var i = 0; i < 7; i++) {
        remoteRack.add(bag.removeLast());
      }
    } else {
      for (var i = 0; i < 7; i++) {
        remoteRack.add(bag.removeLast());
      }
      for (var i = 0; i < 7; i++) {
        localRack.add(bag.removeLast());
      }
    }

    return GameState(
      gameId: gameId,
      localPlayerId: localPlayerId,
      remotePlayerId: remotePlayerId,
      board: Board(),
      bag: bag,
      localRack: localRack,
      remoteRack: remoteRack,
      scores: [0, 0],
      turnSeqNr: 0,
      localPlayerTurn: localGoesFirst,
      prng: prng,
    );
  }

  List<Tile> get currentRack => localPlayerTurn ? localRack : remoteRack;

  void drawTiles(List<Tile> rack, int count) {
    final toDraw = min(count, bag.length);
    for (var i = 0; i < toDraw; i++) {
      rack.add(bag.removeLast());
    }
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
