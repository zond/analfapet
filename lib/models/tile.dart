class Tile {
  final String letter;
  final int points;

  const Tile(this.letter, this.points);

  Map<String, dynamic> toJson() => {'letter': letter};

  factory Tile.fromJson(Map<String, dynamic> json) {
    final letter = json['letter'] as String;
    return Tile(letter, pointValues[letter]!);
  }

  @override
  bool operator ==(Object other) =>
      other is Tile && other.letter == letter && other.points == points;

  @override
  int get hashCode => Object.hash(letter, points);

  @override
  String toString() => '$letter($points)';

  // Point values derived from letter frequency in the Swedish wordlist
  // (freq% ≈ 9.825 * exp(-0.467 * points), inverted and rounded).
  static const Map<String, int> pointValues = {
    'A': 1, 'B': 4, 'C': 6, 'D': 2, 'E': 1, 'F': 4,
    'G': 2, 'H': 5, 'I': 1, 'J': 6, 'K': 2, 'L': 1,
    'M': 3, 'N': 1, 'O': 2, 'P': 3, 'R': 1, 'S': 1,
    'T': 1, 'U': 3, 'V': 4, 'X': 9, 'Y': 5, 'Z': 12,
    'Å': 5, 'Ä': 4, 'Ö': 4, '*': 0, // * = blank tile
  };

  // Swedish Wordfeud tile counts
  static const Map<String, int> tileCounts = {
    'A': 8, 'B': 2, 'C': 1, 'D': 5, 'E': 7, 'F': 2,
    'G': 3, 'H': 2, 'I': 5, 'J': 1, 'K': 3, 'L': 5,
    'M': 3, 'N': 6, 'O': 5, 'P': 2, 'R': 8, 'S': 8,
    'T': 8, 'U': 3, 'V': 3, 'X': 1, 'Y': 1, 'Z': 1,
    'Å': 2, 'Ä': 2, 'Ö': 2, '*': 2,
  };

  static List<Tile> createBag() {
    final bag = <Tile>[];
    for (final entry in tileCounts.entries) {
      for (var i = 0; i < entry.value; i++) {
        bag.add(Tile(entry.key, pointValues[entry.key]!));
      }
    }
    return bag;
  }
}
