import 'package:flutter/material.dart';
import '../models/tile.dart';

class TileRackWidget extends StatelessWidget {
  final List<Tile> tiles;
  final int? selectedIndex;
  final void Function(int index)? onTileTap;

  const TileRackWidget({
    super.key,
    required this.tiles,
    this.selectedIndex,
    this.onTileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(tiles.length, (i) {
        final tile = tiles[i];
        final isSelected = i == selectedIndex;
        return GestureDetector(
          onTap: onTileTap == null ? null : () => onTileTap!(i),
          child: Container(
            width: 44,
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFFFD54F) : const Color(0xFFE8D5B7),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? Colors.orange : const Color(0xFF5D4037),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 2,
                  offset: const Offset(1, 1),
                ),
              ],
            ),
            child: Stack(
              children: [
                Center(
                  child: Text(
                    tile.letter == '*' ? ' ' : tile.letter,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3E2723),
                    ),
                  ),
                ),
                Positioned(
                  right: 3,
                  bottom: 2,
                  child: Text(
                    '${tile.points}',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF5D4037)),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
