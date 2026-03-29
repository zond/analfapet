import 'package:flutter/material.dart';
import '../models/board.dart';

class BoardWidget extends StatelessWidget {
  final Board board;
  final Set<(int, int)> pendingPlacements;
  final void Function(int row, int col)? onCellTap;

  const BoardWidget({
    super.key,
    required this.board,
    this.pendingPlacements = const {},
    this.onCellTap,
  });

  /// Convert a local position to (row, col), given the widget's width.
  static (int, int) positionToCell(Offset local, double boardSize) {
    final cellSize = boardSize / Board.size;
    final col = (local.dx / cellSize).floor().clamp(0, Board.size - 1);
    final row = (local.dy / cellSize).floor().clamp(0, Board.size - 1);
    return (row, col);
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;
          final cellSize = size / Board.size;
          return GestureDetector(
            onTapUp: onCellTap == null
                ? null
                : (details) {
                    final col = (details.localPosition.dx / cellSize).floor().clamp(0, Board.size - 1);
                    final row = (details.localPosition.dy / cellSize).floor().clamp(0, Board.size - 1);
                    onCellTap!(row, col);
                  },
            child: CustomPaint(
              size: Size(size, size),
              painter: _BoardPainter(board, pendingPlacements),
            ),
          );
        },
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  final Board board;
  final Set<(int, int)> pendingPlacements;

  _BoardPainter(this.board, this.pendingPlacements);

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
            '${tile.points}',
            cellSize * 0.25,
            Colors.black54,
          );
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
  bool shouldRepaint(covariant _BoardPainter old) =>
      old.board != board || old.pendingPlacements != pendingPlacements;
}
