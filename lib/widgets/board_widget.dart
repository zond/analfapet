import 'package:flutter/material.dart';
import '../models/board.dart';
import '../models/tile.dart';

class BoardWidget extends StatelessWidget {
  final Board board;
  final Set<(int, int)> pendingPlacements;
  final void Function(int row, int col, Tile tile)? onTileDrop;
  final void Function(int row, int col)? onCellTap;

  const BoardWidget({
    super.key,
    required this.board,
    this.pendingPlacements = const {},
    this.onTileDrop,
    this.onCellTap,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellSize = constraints.maxWidth / Board.size;
          return GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: Board.size,
            ),
            itemCount: Board.size * Board.size,
            itemBuilder: (context, index) {
              final row = index ~/ Board.size;
              final col = index % Board.size;
              return _BoardCell(
                row: row,
                col: col,
                cellSize: cellSize,
                tile: board.get(row, col),
                isPending: pendingPlacements.contains((row, col)),
                bonus: Board.getBonus(row, col),
                isCenter: row == 7 && col == 7,
                onTileDrop: onTileDrop,
                onTap: onCellTap != null ? () => onCellTap!(row, col) : null,
              );
            },
          );
        },
      ),
    );
  }
}

class _BoardCell extends StatelessWidget {
  final int row;
  final int col;
  final double cellSize;
  final PlacedTile? tile;
  final bool isPending;
  final CellBonus bonus;
  final bool isCenter;
  final void Function(int row, int col, Tile tile)? onTileDrop;
  final VoidCallback? onTap;

  const _BoardCell({
    required this.row,
    required this.col,
    required this.cellSize,
    required this.tile,
    required this.isPending,
    required this.bonus,
    required this.isCenter,
    this.onTileDrop,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget cell = Container(
      decoration: BoxDecoration(
        color: _backgroundColor,
        border: Border.all(color: const Color(0xFF5D4037), width: 0.5),
      ),
      child: tile != null
          ? _TileContent(tile: tile!, cellSize: cellSize)
          : _EmptyContent(bonus: bonus, isCenter: isCenter, cellSize: cellSize),
    );

    if (isPending && onTap != null) {
      cell = GestureDetector(onTap: onTap, child: cell);
    }

    if (onTileDrop != null && tile == null) {
      cell = DragTarget<Tile>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (details) => onTileDrop!(row, col, details.data),
        builder: (context, candidateData, rejectedData) {
          if (candidateData.isNotEmpty) {
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.5),
                border: Border.all(color: const Color(0xFF5D4037), width: 0.5),
              ),
              child: _EmptyContent(bonus: bonus, isCenter: isCenter, cellSize: cellSize),
            );
          }
          return cell;
        },
      );
    }

    return cell;
  }

  Color get _backgroundColor {
    if (tile != null) {
      return isPending ? const Color(0xFFFFD54F) : const Color(0xFFE8D5B7);
    }
    return switch (bonus) {
      CellBonus.doubleLetter => const Color(0xFF64B5F6),
      CellBonus.tripleLetter => const Color(0xFF1565C0),
      CellBonus.doubleWord => const Color(0xFFEF9A9A),
      CellBonus.tripleWord => const Color(0xFFC62828),
      CellBonus.none => const Color(0xFF2E7D32),
    };
  }
}

class _TileContent extends StatelessWidget {
  final PlacedTile tile;
  final double cellSize;

  const _TileContent({required this.tile, required this.cellSize});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: Text(
            tile.displayLetter,
            style: TextStyle(
              fontSize: cellSize * 0.55,
              fontWeight: FontWeight.bold,
              color: const Color(0xDD000000),
            ),
          ),
        ),
        Positioned(
          right: 1,
          bottom: 0,
          child: Text(
            '${tile.points}',
            style: TextStyle(
              fontSize: cellSize * 0.25,
              color: const Color(0x8A000000),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyContent extends StatelessWidget {
  final CellBonus bonus;
  final bool isCenter;
  final double cellSize;

  const _EmptyContent({required this.bonus, required this.isCenter, required this.cellSize});

  @override
  Widget build(BuildContext context) {
    if (isCenter) {
      return Center(
        child: Text(
          '\u2605',
          style: TextStyle(fontSize: cellSize * 0.5, color: Colors.white70),
        ),
      );
    }
    if (bonus == CellBonus.none) return const SizedBox.shrink();
    final label = switch (bonus) {
      CellBonus.doubleLetter => 'DL',
      CellBonus.tripleLetter => 'TL',
      CellBonus.doubleWord => 'DW',
      CellBonus.tripleWord => 'TW',
      CellBonus.none => '',
    };
    return Center(
      child: Text(
        label,
        style: TextStyle(fontSize: cellSize * 0.2, color: Colors.white70, fontWeight: FontWeight.bold),
      ),
    );
  }
}
