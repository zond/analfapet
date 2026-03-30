import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'tile.dart';

enum CellBonus { none, doubleLetter, tripleLetter, doubleWord, tripleWord }

class PlacedTile {
  final Tile tile;
  final String? blankLetter; // if tile is blank, what letter it represents

  const PlacedTile(this.tile, {this.blankLetter});

  String get displayLetter =>
      tile.letter == '*' ? (blankLetter ?? '?') : tile.letter;

  int get points => tile.points; // blank always 0

  Map<String, dynamic> toJson() => {
        'tile': tile.toJson(),
        if (blankLetter != null) 'blankLetter': blankLetter,
      };

  factory PlacedTile.fromJson(Map<String, dynamic> json) => PlacedTile(
        Tile.fromJson(json['tile'] as Map<String, dynamic>),
        blankLetter: json['blankLetter'] as String?,
      );
}

class Board {
  static const int size = 15;
  final List<List<PlacedTile?>> cells;

  Board() : cells = List.generate(size, (_) => List.filled(size, null));

  Board.from(Board other)
      : cells = List.generate(
            size, (r) => List.generate(size, (c) => other.cells[r][c]));

  PlacedTile? get(int row, int col) => cells[row][col];

  void set(int row, int col, PlacedTile tile) {
    cells[row][col] = tile;
  }

  bool isEmpty(int row, int col) => cells[row][col] == null;

  bool get isEmptyBoard => cells.every((row) => row.every((cell) => cell == null));

  String computeHash() {
    final buf = StringBuffer();
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        final cell = cells[r][c];
        if (cell != null) {
          buf.write('$r,$c:${cell.displayLetter};');
        }
      }
    }
    return md5.convert(utf8.encode(buf.toString())).toString();
  }

  Map<String, dynamic> toJson() {
    final placed = <Map<String, dynamic>>[];
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (cells[r][c] != null) {
          placed.add({
            'row': r,
            'col': c,
            ...cells[r][c]!.toJson(),
          });
        }
      }
    }
    return {'placed': placed};
  }

  factory Board.fromJson(Map<String, dynamic> json) {
    final board = Board();
    for (final p in json['placed'] as List) {
      final m = p as Map<String, dynamic>;
      board.set(m['row'] as int, m['col'] as int, PlacedTile.fromJson(m));
    }
    return board;
  }

  // Standard Wordfeud-style bonus layout (symmetric)
  static CellBonus getBonus(int row, int col) {
    return _bonusMap[row][col];
  }

  static final List<List<CellBonus>> _bonusMap = _buildBonusMap();

  static List<List<CellBonus>> _buildBonusMap() {
    const n = CellBonus.none;
    const dl = CellBonus.doubleLetter;
    const tl = CellBonus.tripleLetter;
    const dw = CellBonus.doubleWord;
    const tw = CellBonus.tripleWord;

    // Standard 15x15 Wordfeud bonus layout
    return [
      [tw, n,  n,  dl, n,  n,  n,  tw, n,  n,  n,  dl, n,  n,  tw],
      [n,  dw, n,  n,  n,  tl, n,  n,  n,  tl, n,  n,  n,  dw, n ],
      [n,  n,  dw, n,  n,  n,  dl, n,  dl, n,  n,  n,  dw, n,  n ],
      [dl, n,  n,  dw, n,  n,  n,  dl, n,  n,  n,  dw, n,  n,  dl],
      [n,  n,  n,  n,  dw, n,  n,  n,  n,  n,  dw, n,  n,  n,  n ],
      [n,  tl, n,  n,  n,  tl, n,  n,  n,  tl, n,  n,  n,  tl, n ],
      [n,  n,  dl, n,  n,  n,  dl, n,  dl, n,  n,  n,  dl, n,  n ],
      [tw, n,  n,  dl, n,  n,  n,  dw, n,  n,  n,  dl, n,  n,  tw],
      [n,  n,  dl, n,  n,  n,  dl, n,  dl, n,  n,  n,  dl, n,  n ],
      [n,  tl, n,  n,  n,  tl, n,  n,  n,  tl, n,  n,  n,  tl, n ],
      [n,  n,  n,  n,  dw, n,  n,  n,  n,  n,  dw, n,  n,  n,  n ],
      [dl, n,  n,  dw, n,  n,  n,  dl, n,  n,  n,  dw, n,  n,  dl],
      [n,  n,  dw, n,  n,  n,  dl, n,  dl, n,  n,  n,  dw, n,  n ],
      [n,  dw, n,  n,  n,  tl, n,  n,  n,  tl, n,  n,  n,  dw, n ],
      [tw, n,  n,  dl, n,  n,  n,  tw, n,  n,  n,  dl, n,  n,  tw],
    ];
  }
}
