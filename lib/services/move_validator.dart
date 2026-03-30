import '../models/board.dart';
import '../models/move.dart';
import 'dictionary.dart';

class MoveValidationResult {
  final bool valid;
  final String? error;
  final List<String> wordsFormed;
  final int score;

  const MoveValidationResult({
    required this.valid,
    this.error,
    this.wordsFormed = const [],
    this.score = 0,
  });
}

class MoveValidator {
  final Dictionary dictionary;

  MoveValidator(this.dictionary);

  MoveValidationResult validate(Board board, List<TilePlacement> placements, bool isFirstMove) {
    if (placements.isEmpty) {
      return const MoveValidationResult(valid: false, error: 'No tiles placed');
    }

    // Check all placements are on empty cells
    for (final p in placements) {
      if (!board.isEmpty(p.row, p.col)) {
        return MoveValidationResult(valid: false, error: 'Cell (${p.row},${p.col}) is occupied');
      }
      if (p.row < 0 || p.row >= Board.size || p.col < 0 || p.col >= Board.size) {
        return MoveValidationResult(valid: false, error: 'Placement out of bounds');
      }
    }

    // Check tiles are in a single row or column
    final rows = placements.map((p) => p.row).toSet();
    final cols = placements.map((p) => p.col).toSet();
    final isHorizontal = rows.length == 1;
    final isVertical = cols.length == 1;

    if (!isHorizontal && !isVertical) {
      return const MoveValidationResult(valid: false, error: 'Tiles must be in a single row or column');
    }

    // Place tiles on a temporary board
    final tempBoard = Board.from(board);
    for (final p in placements) {
      tempBoard.set(p.row, p.col, p.placedTile);
    }

    // Check contiguity along the main axis
    if (isHorizontal) {
      final row = placements.first.row;
      final minCol = cols.reduce((a, b) => a < b ? a : b);
      final maxCol = cols.reduce((a, b) => a > b ? a : b);
      for (var c = minCol; c <= maxCol; c++) {
        if (tempBoard.isEmpty(row, c)) {
          return const MoveValidationResult(valid: false, error: 'Tiles must be contiguous');
        }
      }
    } else {
      final col = placements.first.col;
      final minRow = rows.reduce((a, b) => a < b ? a : b);
      final maxRow = rows.reduce((a, b) => a > b ? a : b);
      for (var r = minRow; r <= maxRow; r++) {
        if (tempBoard.isEmpty(r, col)) {
          return const MoveValidationResult(valid: false, error: 'Tiles must be contiguous');
        }
      }
    }

    // First move must cover center
    if (isFirstMove) {
      const center = Board.size ~/ 2;
      final coversCenter = placements.any((p) => p.row == center && p.col == center);
      if (!coversCenter) {
        return const MoveValidationResult(valid: false, error: 'First move must cover center');
      }
    } else {
      // Must connect to existing tiles
      final touchesExisting = placements.any((p) => _hasAdjacentTile(board, p.row, p.col));
      if (!touchesExisting) {
        return const MoveValidationResult(valid: false, error: 'Must connect to existing tiles');
      }
    }

    // Find all words formed
    final newTilePositions = {for (final p in placements) (p.row, p.col)};
    final words = <String>[];
    final invalidWords = <String>[];
    var totalScore = 0;

    // Get the main word
    final mainWord = isHorizontal
        ? _getWordAt(tempBoard, placements.first.row, placements.first.col, true)
        : _getWordAt(tempBoard, placements.first.row, placements.first.col, false);

    if (mainWord != null && mainWord.word.length > 1) {
      if (!dictionary.isValid(mainWord.word)) {
        invalidWords.add(mainWord.word);
      } else {
        words.add(mainWord.word);
        totalScore += _scoreWord(tempBoard, mainWord, newTilePositions);
      }
    }

    // Get cross words
    for (final p in placements) {
      final crossWord = isHorizontal
          ? _getWordAt(tempBoard, p.row, p.col, false)
          : _getWordAt(tempBoard, p.row, p.col, true);

      if (crossWord != null && crossWord.word.length > 1) {
        if (!dictionary.isValid(crossWord.word)) {
          invalidWords.add(crossWord.word);
        } else {
          words.add(crossWord.word);
          totalScore += _scoreWord(tempBoard, crossWord, newTilePositions);
        }
      }
    }

    if (invalidWords.isNotEmpty) {
      final quoted = invalidWords.map((w) => '"$w"').join(', ');
      return MoveValidationResult(
        valid: false,
        error: '$quoted — not valid',
      );
    }

    if (words.isEmpty) {
      return const MoveValidationResult(valid: false, error: 'No words formed');
    }

    // Bonus for using all 7 tiles
    if (placements.length == 7) {
      totalScore += 40;
    }

    return MoveValidationResult(valid: true, wordsFormed: words, score: totalScore);
  }

  /// Compute the score for placements without validating words.
  /// Returns 0 if placements are invalid (not in a line, not contiguous, etc.)
  int computeScore(Board board, List<TilePlacement> placements) {
    if (placements.isEmpty) return 0;

    // Check all on empty cells
    for (final p in placements) {
      if (!board.isEmpty(p.row, p.col)) return 0;
      if (p.row < 0 || p.row >= Board.size || p.col < 0 || p.col >= Board.size) return 0;
    }

    final rows = placements.map((p) => p.row).toSet();
    final cols = placements.map((p) => p.col).toSet();
    final isHorizontal = rows.length == 1;
    final isVertical = cols.length == 1;
    if (!isHorizontal && !isVertical) return 0;

    // Place tiles on temp board
    final tempBoard = Board.from(board);
    for (final p in placements) {
      tempBoard.set(p.row, p.col, p.placedTile);
    }

    // Check contiguity
    if (isHorizontal) {
      final row = placements.first.row;
      final minCol = cols.reduce((a, b) => a < b ? a : b);
      final maxCol = cols.reduce((a, b) => a > b ? a : b);
      for (var c = minCol; c <= maxCol; c++) {
        if (tempBoard.isEmpty(row, c)) return 0;
      }
    } else {
      final col = placements.first.col;
      final minRow = rows.reduce((a, b) => a < b ? a : b);
      final maxRow = rows.reduce((a, b) => a > b ? a : b);
      for (var r = minRow; r <= maxRow; r++) {
        if (tempBoard.isEmpty(r, col)) return 0;
      }
    }

    final newTilePositions = {for (final p in placements) (p.row, p.col)};
    var totalScore = 0;

    final mainWord = isHorizontal
        ? _getWordAt(tempBoard, placements.first.row, placements.first.col, true)
        : _getWordAt(tempBoard, placements.first.row, placements.first.col, false);
    if (mainWord != null && mainWord.word.length > 1) {
      totalScore += _scoreWord(tempBoard, mainWord, newTilePositions);
    }

    for (final p in placements) {
      final crossWord = isHorizontal
          ? _getWordAt(tempBoard, p.row, p.col, false)
          : _getWordAt(tempBoard, p.row, p.col, true);
      if (crossWord != null && crossWord.word.length > 1) {
        totalScore += _scoreWord(tempBoard, crossWord, newTilePositions);
      }
    }

    if (placements.length == 7) totalScore += 40;
    return totalScore;
  }

  bool _hasAdjacentTile(Board board, int row, int col) {
    const dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)];
    for (final (dr, dc) in dirs) {
      final r = row + dr, c = col + dc;
      if (r >= 0 && r < Board.size && c >= 0 && c < Board.size && !board.isEmpty(r, c)) {
        return true;
      }
    }
    return false;
  }

  _WordSpan? _getWordAt(Board board, int row, int col, bool horizontal) {
    if (horizontal) {
      var startCol = col;
      while (startCol > 0 && !board.isEmpty(row, startCol - 1)) {
        startCol--;
      }
      var endCol = col;
      while (endCol < Board.size - 1 && !board.isEmpty(row, endCol + 1)) {
        endCol++;
      }
      if (startCol == endCol) return null;
      final buf = StringBuffer();
      final positions = <(int, int)>[];
      for (var c = startCol; c <= endCol; c++) {
        buf.write(board.get(row, c)!.displayLetter);
        positions.add((row, c));
      }
      return _WordSpan(buf.toString(), positions, horizontal);
    } else {
      var startRow = row;
      while (startRow > 0 && !board.isEmpty(startRow - 1, col)) {
        startRow--;
      }
      var endRow = row;
      while (endRow < Board.size - 1 && !board.isEmpty(endRow + 1, col)) {
        endRow++;
      }
      if (startRow == endRow) return null;
      final buf = StringBuffer();
      final positions = <(int, int)>[];
      for (var r = startRow; r <= endRow; r++) {
        buf.write(board.get(r, col)!.displayLetter);
        positions.add((r, col));
      }
      return _WordSpan(buf.toString(), positions, horizontal);
    }
  }

  int _scoreWord(Board board, _WordSpan span, Set<(int, int)> newTiles) {
    var wordMultiplier = 1;
    var wordScore = 0;

    for (final (row, col) in span.positions) {
      final tile = board.get(row, col)!;
      var letterScore = tile.points;

      if (newTiles.contains((row, col))) {
        final bonus = Board.getBonus(row, col);
        switch (bonus) {
          case CellBonus.doubleLetter:
            letterScore *= 2;
          case CellBonus.tripleLetter:
            letterScore *= 3;
          case CellBonus.doubleWord:
            wordMultiplier *= 2;
          case CellBonus.tripleWord:
            wordMultiplier *= 3;
          case CellBonus.none:
            break;
        }
      }
      wordScore += letterScore;
    }

    return wordScore * wordMultiplier;
  }
}

class _WordSpan {
  final String word;
  final List<(int, int)> positions;
  final bool horizontal;

  _WordSpan(this.word, this.positions, this.horizontal);
}
