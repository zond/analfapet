import 'package:flutter/services.dart';

class Dictionary {
  final Set<String> _words = {};
  bool _loaded = false;

  Future<void> load() async {
    final text = await rootBundle.loadString('assets/wordlist.txt');
    var start = 0;
    while (start < text.length) {
      var end = text.indexOf('\n', start);
      if (end == -1) end = text.length;
      if (end > start) {
        final word = text.substring(start, end).trim();
        if (word.isNotEmpty && word.length <= 15) {
          _words.add(word.toUpperCase());
        }
      }
      start = end + 1;
    }
    _loaded = true;
  }

  bool get isLoaded => _loaded;

  bool isValid(String word) => _words.contains(word.toUpperCase());

  int get wordCount => _words.length;
}
