import 'package:flutter/material.dart';
import '../models/game_state.dart';
import '../models/remote_game.dart';
import '../services/dictionary.dart';
import '../services/remote_game_controller.dart';
import 'game_screen.dart';

/// Wrapper that reconstructs GameState from a RemoteGame and renders GameScreen.
class RemoteGameScreen extends StatefulWidget {
  final String gameId;
  final RemoteGameController controller;
  final Dictionary dictionary;
  final String myId;

  const RemoteGameScreen({
    super.key,
    required this.gameId,
    required this.controller,
    required this.dictionary,
    required this.myId,
  });

  @override
  State<RemoteGameScreen> createState() => _RemoteGameScreenState();
}

class _RemoteGameScreenState extends State<RemoteGameScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.controller.games
        .cast<RemoteGame?>()
        .firstWhere((g) => g!.gameId == widget.gameId, orElse: () => null);

    if (game == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF1B5E20),
        appBar: AppBar(
          title: const Text('Game not found'),
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text('Game was deleted', style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    if (!game.allAccepted) {
      final waiting = game.players.where((p) => !p.accepted).map((p) => p.name);
      return Scaffold(
        backgroundColor: const Color(0xFF1B5E20),
        appBar: AppBar(
          title: const Text('Waiting'),
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.greenAccent),
              const SizedBox(height: 16),
              Text(
                'Waiting for ${waiting.join(", ")} to accept',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final localPlayerIndex = game.playerIndex(widget.myId);
    final playerNames = game.players.map((p) => p.uuid == widget.myId ? 'You' : p.name).toList();

    final gameState = GameState.replayFromMoves(
      gameId: game.gameId,
      playerCount: game.players.length,
      seed: game.seed,
      moves: game.moves,
    );

    return GameScreen(
      gameState: gameState,
      dictionary: widget.dictionary,
      localPlayerIndex: localPlayerIndex,
      playerNames: playerNames,
      onMoveSubmitted: (move) async {
        await widget.controller.sendMove(game.gameId, move);
      },
      onHurry: gameState.currentPlayer != localPlayerIndex
          ? () async {
              final targetUuid = game.players[gameState.currentPlayer].uuid;
              await widget.controller.sendHurry(game.gameId, targetUuid);
            }
          : null,
    );
  }
}
