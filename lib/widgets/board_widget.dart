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

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellSize = constraints.maxWidth / Board.size;
          return GestureDetector(
            onTapUp: onCellTap == null
                ? null
                : (details) {
                    final col = (details.localPosition.dx / cellSize).floor().clamp(0, Board.size - 1);
                    final row = (details.localPosition.dy / cellSize).floor().clamp(0, Board.size - 1);
                    onCellTap!(row, col);
                  },
            child: CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxWidth),
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
          // Placed tile
          final isPending = pendingPlacements.contains((r, c));
          final paint = Paint()
            ..color = isPending ? const Color(0xFFFFD54F) : const Color(0xFFE8D5B7);
          canvas.drawRect(rect, paint);

          _drawText(canvas, rect, tile.displayLetter, cellSize * 0.55, Colors.black87);
          _drawText(
            canvas,
            Rect.fromLTWH(rect.left + cellSize * 0.55, rect.top + cellSize * 0.55, cellSize * 0.4, cellSize * 0.4),
            '${tile.points}',
            cellSize * 0.25,
            Colors.black54,
          );
        } else {
          // Empty cell with bonus
          final bonus = Board.getBonus(r, c);
          final paint = Paint()..color = _bonusColor(bonus);
          canvas.drawRect(rect, paint);

          if (bonus != CellBonus.none) {
            _drawText(canvas, rect, _bonusLabel(bonus), cellSize * 0.2, Colors.white70);
          }
        }

        // Grid lines
        final borderPaint = Paint()
          ..color = const Color(0xFF5D4037)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;
        canvas.drawRect(rect, borderPaint);
      }
    }

    // Center star
    if (board.isEmpty(7, 7)) {
      final center = Rect.fromLTWH(7 * cellSize, 7 * cellSize, cellSize, cellSize);
      _drawText(canvas, center, '\u2605', cellSize * 0.5, Colors.white70);
    }
  }

  void _drawText(Canvas canvas, Rect rect, String text, double fontSize, Color color) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        rect.left + (rect.width - textPainter.width) / 2,
        rect.top + (rect.height - textPainter.height) / 2,
      ),
    );
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
  bool shouldRepaint(covariant _BoardPainter oldDelegate) => true;
}
