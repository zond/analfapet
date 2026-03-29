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

  // Drag state
  Tile? _dragTile;
  Offset _dragPosition = Offset.zero;

  // Board hit testing
  final GlobalKey _boardKey = GlobalKey();

  GameState get game => widget.gameState;

  @override
  void initState() {
    super.initState();
    _validator = MoveValidator(widget.dictionary);
  }

  // --- Drag handling ---

  void _onRackTileDragStart(int index, Offset globalPosition) {
    setState(() {
      _dragTile = game.currentRack[index];
      _dragPosition = globalPosition;
      game.currentRack.removeAt(index);
    });
  }

  void _onBoardTileDragStart(int row, int col, Offset globalPosition) {
    final idx = _pendingPlacements.indexWhere((p) => p.row == row && p.col == col);
    if (idx < 0) return;
    setState(() {
      final removed = _pendingPlacements.removeAt(idx);
      _dragTile = removed.placedTile.tile;
      _dragPosition = globalPosition;
    });
  }

  void _onDragUpdate(Offset globalPosition) {
    setState(() {
      _dragPosition = globalPosition;
    });
  }

  void _onDragEnd() {
    if (_dragTile == null) return;

    // Check if dropped on the board
    final boardBox = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (boardBox != null) {
      final local = boardBox.globalToLocal(_dragPosition);
      final boardSize = boardBox.size.width;
      if (local.dx >= 0 && local.dx < boardSize && local.dy >= 0 && local.dy < boardSize) {
        final (row, col) = BoardWidget.positionToCell(local, boardSize);
        if (game.board.isEmpty(row, col) && !_pendingPlacements.any((p) => p.row == row && p.col == col)) {
          if (_dragTile!.letter == '*') {
            // For blank tiles, show picker then place
            final tile = _dragTile!;
            setState(() {
              _dragTile = null;
  
            });
            _showBlankLetterPicker(row, col, tile);
            return;
          }
          setState(() {
            _pendingPlacements.add(TilePlacement(row, col, PlacedTile(_dragTile!)));
            _dragTile = null;

          });
          return;
        }
      }
    }

    // Not dropped on valid cell — return to rack
    setState(() {
      game.currentRack.add(_dragTile!);
      _dragTile = null;
    });
  }

  // --- Cell tap (to pick up pending tiles) ---

  void _onCellTap(int row, int col) {
    final existingIndex = _pendingPlacements.indexWhere((p) => p.row == row && p.col == col);
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
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
        });
      } else {
        // Cancelled — return to rack
        setState(() {
          game.currentRack.add(tile);
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
    final result = _validator.validate(game.board, _pendingPlacements, isFirstMove);

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
        content: Text('${result.wordsFormed.join(", ")} — ${result.score} points!'),
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
                    fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(_scoreText, style: const TextStyle(fontSize: 20, color: Colors.white70)),
                const SizedBox(height: 32),
                const Text('Tap to start your turn',
                    style: TextStyle(color: Colors.white54, fontSize: 18)),
              ],
            ),
          ),
        ),
      );
    }

    final pendingPositions = {for (final p in _pendingPlacements) (p.row, p.col)};

    return Listener(
      onPointerMove: _dragTile != null ? (e) => _onDragUpdate(e.position) : null,
      onPointerUp: _dragTile != null ? (_) => _onDragEnd() : null,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: const Color(0xFF1B5E20),
            appBar: AppBar(
              title: Text(game.currentPlayerName),
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              actions: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: Text(_scoreText,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                      Text('Tiles left: ${game.bag.length}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      Text('Turn ${game.turnSeqNr + 1}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _BoardWithDrag(
                      key: _boardKey,
                      board: _boardWithPending,
                      pendingPlacements: pendingPositions,
                      onCellTap: _onCellTap,
                      onPendingDragStart: _onBoardTileDragStart,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TileRackWidget(
                  tiles: game.currentRack,
                  onTileDragStart: _onRackTileDragStart,
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
                        onPressed: _pendingPlacements.isNotEmpty ? _recallTiles : null,
                        icon: const Icon(Icons.undo),
                        tooltip: 'Recall tiles',
                        color: Colors.white70,
                      ),
                      ElevatedButton.icon(
                        onPressed: _pendingPlacements.isNotEmpty ? _submitMove : null,
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
          ),
          // Drag overlay
          if (_dragTile != null)
            Positioned(
              left: _dragPosition.dx - 25,
              top: _dragPosition.dy - 25,
              child: IgnorePointer(
                child: TileWidget(tile: _dragTile!, size: 50, dragging: true),
              ),
            ),
        ],
      ),
    );
  }
}

/// Board wrapper that detects drag starts on pending tiles.
class _BoardWithDrag extends StatelessWidget {
  final Board board;
  final Set<(int, int)> pendingPlacements;
  final void Function(int row, int col)? onCellTap;
  final void Function(int row, int col, Offset globalPosition)? onPendingDragStart;

  const _BoardWithDrag({
    super.key,
    required this.board,
    this.pendingPlacements = const {},
    this.onCellTap,
    this.onPendingDragStart,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        return GestureDetector(
          onTapUp: onCellTap == null
              ? null
              : (details) {
                  final (row, col) = BoardWidget.positionToCell(details.localPosition, size);
                  onCellTap!(row, col);
                },
          onPanStart: onPendingDragStart == null
              ? null
              : (details) {
                  final (row, col) = BoardWidget.positionToCell(details.localPosition, size);
                  if (pendingPlacements.contains((row, col))) {
                    onPendingDragStart!(row, col, details.globalPosition);
                  }
                },
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              size: Size(size, size),
              painter: _SimpleBoardPainter(board, pendingPlacements),
            ),
          ),
        );
      },
    );
  }
}

class _SimpleBoardPainter extends CustomPainter {
  final Board board;
  final Set<(int, int)> pendingPlacements;

  _SimpleBoardPainter(this.board, this.pendingPlacements);

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = size.width / Board.size;

    for (var r = 0; r < Board.size; r++) {
      for (var c = 0; c < Board.size; c++) {
        final rect = Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize);
        final tile = board.get(r, c);

        if (tile != null) {
          final isPending = pendingPlacements.contains((r, c));
          canvas.drawRect(rect, Paint()..color = isPending ? const Color(0xFFFFD54F) : const Color(0xFFE8D5B7));
          _drawText(canvas, rect, tile.displayLetter, cellSize * 0.55, Colors.black87);
          _drawText(
            canvas,
            Rect.fromLTWH(rect.left + cellSize * 0.55, rect.top + cellSize * 0.55, cellSize * 0.4, cellSize * 0.4),
            '${tile.points}', cellSize * 0.25, Colors.black54,
          );
        } else {
          final bonus = Board.getBonus(r, c);
          canvas.drawRect(rect, Paint()..color = _bonusColor(bonus));
          if (bonus != CellBonus.none) {
            _drawText(canvas, rect, _bonusLabel(bonus), cellSize * 0.2, Colors.white70);
          }
        }

        canvas.drawRect(rect, Paint()
          ..color = const Color(0xFF5D4037)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5);
      }
    }

    if (board.isEmpty(7, 7)) {
      final center = Rect.fromLTWH(7 * cellSize, 7 * cellSize, cellSize, cellSize);
      _drawText(canvas, center, '\u2605', cellSize * 0.5, Colors.white70);
    }
  }

  void _drawText(Canvas canvas, Rect rect, String text, double fontSize, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(rect.left + (rect.width - tp.width) / 2, rect.top + (rect.height - tp.height) / 2));
  }

  Color _bonusColor(CellBonus bonus) => switch (bonus) {
    CellBonus.doubleLetter => const Color(0xFF64B5F6),
    CellBonus.tripleLetter => const Color(0xFF1565C0),
    CellBonus.doubleWord => const Color(0xFFEF9A9A),
    CellBonus.tripleWord => const Color(0xFFC62828),
    CellBonus.none => const Color(0xFF2E7D32),
  };

  String _bonusLabel(CellBonus bonus) => switch (bonus) {
    CellBonus.doubleLetter => 'DL',
    CellBonus.tripleLetter => 'TL',
    CellBonus.doubleWord => 'DW',
    CellBonus.tripleWord => 'TW',
    CellBonus.none => '',
  };

  @override
  bool shouldRepaint(covariant _SimpleBoardPainter old) =>
      old.board != board || old.pendingPlacements != pendingPlacements;
}
