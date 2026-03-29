import 'package:flutter/material.dart';
import '../models/tile.dart';
import 'board_widget.dart';

class TileRackWidget extends StatelessWidget {
  final List<Tile> tiles;
  final bool enabled;
  final void Function(Tile tile)? onTileReturnedToRack;

  const TileRackWidget({
    super.key,
    required this.tiles,
    this.enabled = true,
    this.onTileReturnedToRack,
  });

  @override
  Widget build(BuildContext context) {
    Widget rack = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(tiles.length, (i) {
        final tile = tiles[i];
        final child = TileWidget(tile: tile);
        if (!enabled) return Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: child);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Draggable<Tile>(
            data: tile,
            feedback: Material(
              color: Colors.transparent,
              child: TileWidget(tile: tile, size: 50, dragging: true),
            ),
            childWhenDragging: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF1B5E20),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF5D4037), width: 1),
              ),
            ),
            child: child,
          ),
        );
      }),
    );

    if (onTileReturnedToRack != null) {
      rack = DragTarget<Object>(
        onWillAcceptWithDetails: (details) {
          // Only accept tiles dragged from the board
          return details.data is BoardTileDrag;
        },
        onAcceptWithDetails: (details) {
          if (details.data is BoardTileDrag) {
            onTileReturnedToRack!((details.data as BoardTileDrag).tile);
          }
        },
        builder: (context, candidateData, rejectedData) {
          if (candidateData.isNotEmpty) {
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: const Color(0x304CAF50),
              ),
              child: rack,
            );
          }
          return rack;
        },
      );
    }

    return rack;
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
