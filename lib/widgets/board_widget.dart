import 'package:flutter/material.dart';
import '../models/board.dart';
import '../models/tile.dart';
import 'tile_rack_widget.dart';

/// Data for a tile being dragged from the board.
class BoardTileDrag {
  final Tile tile;
  final int fromRow;
  final int fromCol;

  const BoardTileDrag(this.tile, this.fromRow, this.fromCol);
}

class BoardWidget extends StatefulWidget {
  final Board board;
  final Set<(int, int)> pendingPlacements;
  final void Function(int row, int col, Tile tile)? onTileDrop;
  final void Function(int row, int col)? onPendingTilePickedUp;
  final void Function(int row, int col)? onCellTap;

  const BoardWidget({
    super.key,
    required this.board,
    this.pendingPlacements = const {},
    this.onTileDrop,
    this.onPendingTilePickedUp,
    this.onCellTap,
  });

  @override
  State<BoardWidget> createState() => _BoardWidgetState();
}

class _BoardWidgetState extends State<BoardWidget> {
  (int, int)? _hoverCell;
  (int, int)? _draggingFrom;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;
          final cellSize = size / Board.size;

          return DragTarget<Object>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (details) {
              if (widget.onTileDrop == null) return;
              final box = context.findRenderObject() as RenderBox;
              final local = box.globalToLocal(details.offset);
              final col = (local.dx / cellSize).floor().clamp(0, Board.size - 1);
              final row = (local.dy / cellSize).floor().clamp(0, Board.size - 1);
              final data = details.data;
              if (data is Tile) {
                widget.onTileDrop!(row, col, data);
              } else if (data is BoardTileDrag) {
                widget.onTileDrop!(row, col, data.tile);
              }
              setState(() => _hoverCell = null);
            },
            onMove: (details) {
              final box = context.findRenderObject() as RenderBox;
              final local = box.globalToLocal(details.offset);
              final col = (local.dx / cellSize).floor().clamp(0, Board.size - 1);
              final row = (local.dy / cellSize).floor().clamp(0, Board.size - 1);
              final cell = (row, col);
              if (_hoverCell != cell) setState(() => _hoverCell = cell);
            },
            onLeave: (_) => setState(() => _hoverCell = null),
            builder: (context, candidateData, rejectedData) {
              return SizedBox(
                width: size,
                height: size,
                child: Stack(
                children: [
                  GestureDetector(
                    onTapUp: widget.onCellTap == null
                        ? null
                        : (details) {
                            final col = (details.localPosition.dx / cellSize).floor().clamp(0, Board.size - 1);
                            final row = (details.localPosition.dy / cellSize).floor().clamp(0, Board.size - 1);
                            widget.onCellTap!(row, col);
                          },
                    child: CustomPaint(
                      size: Size(size, size),
                      painter: _BoardPainter(
                        widget.board,
                        widget.pendingPlacements,
                        _draggingFrom,
                        candidateData.isNotEmpty ? _hoverCell : null,
                      ),
                    ),
                  ),
                  // Overlay draggable widgets on pending placements
                  for (final (r, c) in widget.pendingPlacements)
                    if (widget.board.get(r, c) != null)
                      Positioned(
                        left: c * cellSize,
                        top: r * cellSize,
                        width: cellSize,
                        height: cellSize,
                        child: Draggable<BoardTileDrag>(
                          data: BoardTileDrag(widget.board.get(r, c)!.tile, r, c),
                          onDragStarted: () {
                            widget.onPendingTilePickedUp?.call(r, c);
                            setState(() => _draggingFrom = (r, c));
                          },
                          onDragEnd: (_) => setState(() => _draggingFrom = null),
                          onDraggableCanceled: (_, _) => setState(() => _draggingFrom = null),
                          feedback: Material(
                            color: Colors.transparent,
                            child: TileWidget(
                              tile: widget.board.get(r, c)!.tile,
                              size: cellSize * 1.2,
                              dragging: true,
                            ),
                          ),
                          childWhenDragging: const SizedBox.shrink(),
                          child: const SizedBox.expand(), // transparent hit area
                        ),
                      ),
                ],
              ),
              );
            },
          );
        },
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  final Board board;
  final Set<(int, int)> pendingPlacements;
  final (int, int)? draggingFrom;
  final (int, int)? hoverCell;

  _BoardPainter(this.board, this.pendingPlacements, this.draggingFrom, this.hoverCell);

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = size.width / Board.size;

    for (var r = 0; r < Board.size; r++) {
      for (var c = 0; c < Board.size; c++) {
        final rect = Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize);
        final tile = board.get(r, c);
        final isDragging = draggingFrom == (r, c);

        if (tile != null && !isDragging) {
          final isPending = pendingPlacements.contains((r, c));
          canvas.drawRect(rect, Paint()..color = isPending ? const Color(0xFFFFD54F) : const Color(0xFFE8D5B7));
          _drawText(canvas, rect, tile.displayLetter, cellSize * 0.55, Colors.black87);
          _drawText(
            canvas,
            Rect.fromLTWH(rect.left + cellSize * 0.55, rect.top + cellSize * 0.55, cellSize * 0.4, cellSize * 0.4),
            '${tile.points}',
            cellSize * 0.25,
            Colors.black54,
          );
        } else if (hoverCell == (r, c)) {
          canvas.drawRect(rect, Paint()..color = const Color(0x804CAF50));
        } else {
          final bonus = Board.getBonus(r, c);
          canvas.drawRect(rect, Paint()..color = _bonusColor(bonus));
          if (bonus != CellBonus.none) {
            _drawText(canvas, rect, _bonusLabel(bonus), cellSize * 0.2, Colors.white70);
          }
        }

        canvas.drawRect(
          rect,
          Paint()
            ..color = const Color(0xFF5D4037)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5,
        );
      }
    }

    if (board.isEmpty(7, 7) && hoverCell != (7, 7)) {
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
  bool shouldRepaint(covariant _BoardPainter old) => true;
}
