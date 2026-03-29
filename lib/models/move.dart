import 'board.dart';

enum MoveType { play, pass, swap, resign }

class TilePlacement {
  final int row;
  final int col;
  final PlacedTile placedTile;

  const TilePlacement(this.row, this.col, this.placedTile);

  Map<String, dynamic> toJson() => {
        'row': row,
        'col': col,
        ...placedTile.toJson(),
      };

  factory TilePlacement.fromJson(Map<String, dynamic> json) => TilePlacement(
        json['row'] as int,
        json['col'] as int,
        PlacedTile.fromJson(json),
      );
}

class Move {
  final MoveType type;
  final int turnSeqNr;
  final String boardHash;
  final List<TilePlacement> placements;
  final int score;

  const Move({
    required this.type,
    required this.turnSeqNr,
    required this.boardHash,
    this.placements = const [],
    this.score = 0,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'turnSeqNr': turnSeqNr,
        'boardHash': boardHash,
        'placements': placements.map((p) => p.toJson()).toList(),
        'score': score,
      };

  factory Move.fromJson(Map<String, dynamic> json) => Move(
        type: MoveType.values.byName(json['type'] as String),
        turnSeqNr: json['turnSeqNr'] as int,
        boardHash: json['boardHash'] as String,
        placements: (json['placements'] as List)
            .map((p) => TilePlacement.fromJson(p as Map<String, dynamic>))
            .toList(),
        score: json['score'] as int,
      );
}
