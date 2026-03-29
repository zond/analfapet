import 'package:flutter/services.dart';

class Dictionary {
  late final Set<String> _words;

  Future<void> load() async {
    final text = await rootBundle.loadString('assets/wordlist.txt');
    _words = text
        .split('\n')
        .map((w) => w.trim().toUpperCase())
        .where((w) => w.isNotEmpty)
        .toSet();
  }

  bool isValid(String word) => _words.contains(word.toUpperCase());

  int get wordCount => _words.length;
}
