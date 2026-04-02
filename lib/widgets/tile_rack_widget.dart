import 'package:flutter/material.dart';
import '../models/tile.dart';

class TileRackWidget extends StatelessWidget {
  final List<Tile> tiles;
  final void Function(int index, Offset globalPosition)? onTileDragStart;
  /// Index where a dragged tile would be inserted (shows a gap).
  /// null means no drag is happening over the rack.
  final int? hoverInsertIndex;

  const TileRackWidget({
    super.key,
    required this.tiles,
    this.onTileDragStart,
    this.hoverInsertIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(tiles.length + (hoverInsertIndex != null ? 1 : 0), (i) {
        // Insert a gap at the hover position
        if (hoverInsertIndex != null && i == hoverInsertIndex) {
          return const SizedBox(width: 48, height: 44); // gap
        }
        // Adjust index for tiles after the gap
        final tileIdx = hoverInsertIndex != null && i > hoverInsertIndex! ? i - 1 : i;
        if (tileIdx >= tiles.length) return const SizedBox.shrink();
        final tile = tiles[tileIdx];
        return GestureDetector(
          onPanStart: onTileDragStart == null
              ? null
              : (details) => onTileDragStart!(tileIdx, details.globalPosition),
          child: TileWidget(tile: tile),
        );
      }),
    );
  }
}

class TileWidget extends StatelessWidget {
  final Tile tile;
  final double size;
  final bool dragging;

  const TileWidget({
    super.key,
    required this.tile,
    this.size = 44,
    this.dragging = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: dragging ? const Color(0xFFFFD54F) : const Color(0xFFE8D5B7),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: dragging ? Colors.orange : const Color(0xFF5D4037),
          width: dragging ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dragging ? 0.4 : 0.2),
            blurRadius: dragging ? 6 : 2,
            offset: dragging ? const Offset(2, 2) : const Offset(1, 1),
          ),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              tile.letter == '*' ? ' ' : tile.letter,
              style: TextStyle(
                fontSize: size * 0.5,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF3E2723),
              ),
            ),
          ),
          Positioned(
            right: 3,
            bottom: 2,
            child: Text(
              '${tile.points}',
              style: TextStyle(fontSize: size * 0.22, color: const Color(0xFF5D4037)),
            ),
          ),
        ],
      ),
    );
  }
}
