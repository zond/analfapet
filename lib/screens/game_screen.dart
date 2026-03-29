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
  bool _handover = false;

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
        game.currentRack.remove(tile);
      });
    }
  }

  void _onPendingTilePickedUp(int row, int col) {
    setState(() {
      final idx = _pendingPlacements.indexWhere((p) => p.row == row && p.col == col);
      if (idx >= 0) {
        _pendingPlacements.removeAt(idx);
        // Don't add back to rack — it's now being dragged
      }
    });
  }

  void _onTileReturnedToRack(Tile tile) {
    setState(() {
      game.currentRack.add(tile);
    });
  }

  void _onCellTap(int row, int col) {
    final existingIndex =
        _pendingPlacements.indexWhere((p) => p.row == row && p.col == col);
    if (existingIndex >= 0) {
      setState(() {
        final removed = _pendingPlacements.removeAt(existingIndex);
        game.currentRack.add(removed.placedTile.tile);
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
          game.currentRack.remove(tile);
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

  void _endTurn() {
    setState(() {
      _pendingPlacements.clear();
      game.nextTurn();
      _handover = true;
    });
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

    for (final p in _pendingPlacements) {
      game.board.set(p.row, p.col, p.placedTile);
    }
    game.scores[game.currentPlayer] += result.score;
    game.drawTiles(game.currentRack, _pendingPlacements.length);
    game.consecutivePasses = 0;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '${result.wordsFormed.join(", ")} — ${result.score} points!'),
      ),
    );

    _endTurn();
  }

  void _recallTiles() {
    setState(() {
      for (final p in _pendingPlacements) {
        game.currentRack.add(p.placedTile.tile);
      }
      _pendingPlacements.clear();
    });
  }

  void _shuffleRack() {
    setState(() {
      game.currentRack.shuffle();
    });
  }

  void _pass() {
    game.consecutivePasses++;
    _endTurn();
  }

  String get _scoreText {
    final parts = <String>[];
    for (var i = 0; i < game.playerCount; i++) {
      parts.add('P${i + 1}: ${game.scores[i]}');
    }
    return parts.join('  ');
  }

  @override
  Widget build(BuildContext context) {
    if (_handover) {
      return Scaffold(
        backgroundColor: const Color(0xFF1B5E20),
        body: GestureDetector(
          onTap: () => setState(() => _handover = false),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  game.currentPlayerName,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _scoreText,
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Tap to start your turn',
                  style: TextStyle(color: Colors.white54, fontSize: 18),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final pendingPositions = {
      for (final p in _pendingPlacements) (p.row, p.col)
    };

    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: Text(game.currentPlayerName),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                _scoreText,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
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
                onTileDrop: _onTileDrop,
                onPendingTilePickedUp: _onPendingTilePickedUp,
                onCellTap: _onCellTap,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TileRackWidget(
            tiles: game.currentRack,
            onTileReturnedToRack: _onTileReturnedToRack,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: _shuffleRack,
                  icon: const Icon(Icons.shuffle),
                  tooltip: 'Shuffle rack',
                  color: Colors.white70,
                ),
                IconButton(
                  onPressed:
                      _pendingPlacements.isNotEmpty ? _recallTiles : null,
                  icon: const Icon(Icons.undo),
                  tooltip: 'Recall tiles',
                  color: Colors.white70,
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
                IconButton(
                  onPressed: _pass,
                  icon: const Icon(Icons.skip_next),
                  tooltip: 'Pass',
                  color: Colors.white70,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
