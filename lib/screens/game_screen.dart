import 'package:flutter/material.dart';
import '../models/board.dart';
import '../models/game_state.dart';
import '../models/move.dart';
import '../models/tile.dart';
import '../services/dictionary.dart';
import '../services/move_validator.dart';
import '../widgets/board_widget.dart';
import '../widgets/tile_rack_widget.dart';

class GameScreen extends StatefulWidget {
  final GameState gameState;
  final Dictionary dictionary;

  const GameScreen({
    super.key,
    required this.gameState,
    required this.dictionary,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final List<TilePlacement> _pendingPlacements = [];
  late final MoveValidator _validator;

  GameState get game => widget.gameState;

  @override
  void initState() {
    super.initState();
    _validator = MoveValidator(widget.dictionary);
  }

  void _onTileDrop(int row, int col, Tile tile) {
    if (!game.board.isEmpty(row, col)) return;
    if (_pendingPlacements.any((p) => p.row == row && p.col == col)) return;

    if (tile.letter == '*') {
      _showBlankLetterPicker(row, col, tile);
    } else {
      setState(() {
        _pendingPlacements.add(TilePlacement(row, col, PlacedTile(tile)));
        game.localRack.remove(tile);
      });
    }
  }

  void _onCellTap(int row, int col) {
    // Tap a pending placement to return it to rack
    final existingIndex =
        _pendingPlacements.indexWhere((p) => p.row == row && p.col == col);
    if (existingIndex >= 0) {
      setState(() {
        final removed = _pendingPlacements.removeAt(existingIndex);
        game.localRack.add(removed.placedTile.tile);
      });
    }
  }

  void _showBlankLetterPicker(int row, int col, Tile tile) {
    showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose letter'),
        content: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: 'ABCDEFGHIJKLMNOPRSTUVXYÅÄÖ'.split('').map((letter) {
            return InkWell(
              onTap: () => Navigator.pop(context, letter),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8D5B7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(letter,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            );
          }).toList(),
        ),
      ),
    ).then((letter) {
      if (letter != null) {
        setState(() {
          _pendingPlacements.add(
            TilePlacement(row, col, PlacedTile(tile, blankLetter: letter)),
          );
          game.localRack.remove(tile);
        });
      }
    });
  }

  Board get _boardWithPending {
    final tempBoard = Board.from(game.board);
    for (final p in _pendingPlacements) {
      tempBoard.set(p.row, p.col, p.placedTile);
    }
    return tempBoard;
  }

  void _submitMove() {
    final isFirstMove = game.turnSeqNr == 0;
    final result =
        _validator.validate(game.board, _pendingPlacements, isFirstMove);

    if (!result.valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error!)),
      );
      return;
    }

    setState(() {
      for (final p in _pendingPlacements) {
        game.board.set(p.row, p.col, p.placedTile);
      }
      game.scores[0] += result.score;
      game.drawTiles(game.localRack, _pendingPlacements.length);
      game.turnSeqNr++;
      game.localPlayerTurn = false;
      game.consecutivePasses = 0;
      _pendingPlacements.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '${result.wordsFormed.join(", ")} — ${result.score} points!'),
      ),
    );

    // TODO: send move via FCM
  }

  void _recallTiles() {
    setState(() {
      for (final p in _pendingPlacements) {
        game.localRack.add(p.placedTile.tile);
      }
      _pendingPlacements.clear();
    });
  }

  void _pass() {
    setState(() {
      game.turnSeqNr++;
      game.localPlayerTurn = false;
      game.consecutivePasses++;
      _pendingPlacements.clear();
    });
    // TODO: send pass via FCM
  }

  @override
  Widget build(BuildContext context) {
    final pendingPositions = {
      for (final p in _pendingPlacements) (p.row, p.col)
    };

    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: const Text('Analfapet'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                '${game.scores[0]} – ${game.scores[1]}',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tiles left: ${game.bag.length}',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Text(
                  game.localPlayerTurn ? 'Your turn' : 'Waiting...',
                  style: TextStyle(
                    color: game.localPlayerTurn
                        ? Colors.greenAccent
                        : Colors.white54,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Turn ${game.turnSeqNr + 1}',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: BoardWidget(
                board: _boardWithPending,
                pendingPlacements: pendingPositions,
                onTileDrop: game.localPlayerTurn ? _onTileDrop : null,
                onCellTap: game.localPlayerTurn ? _onCellTap : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TileRackWidget(
            tiles: game.localRack,
            enabled: game.localPlayerTurn,
          ),
          const SizedBox(height: 8),
          if (game.localPlayerTurn)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed:
                        _pendingPlacements.isNotEmpty ? _recallTiles : null,
                    icon: const Icon(Icons.undo),
                    label: const Text('Recall'),
                  ),
                  ElevatedButton.icon(
                    onPressed:
                        _pendingPlacements.isNotEmpty ? _submitMove : null,
                    icon: const Icon(Icons.check),
                    label: const Text('Play'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _pass,
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Pass'),
                  ),
                ],
              ),
            ),
          if (!game.localPlayerTurn)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Waiting for opponent...',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            ),
        ],
      ),
    );
  }
}
