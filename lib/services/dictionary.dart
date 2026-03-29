import 'dart:convert';
import 'package:flutter/services.dart';

class Dictionary {
  late final Set<String> _words;

  Future<void> load() async {
    final data = await rootBundle.load('assets/wordlist.txt');
    final bytes = data.buffer.asUint8List();
    final words = <String>{};
    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0x0A) { // newline
        if (i > start) {
          final word = utf8.decode(bytes.sublist(start, i)).trim().toUpperCase();
          if (word.isNotEmpty) words.add(word);
        }
        start = i + 1;
      }
    }
    // last line without trailing newline
    if (start < bytes.length) {
      final word = utf8.decode(bytes.sublist(start)).trim().toUpperCase();
      if (word.isNotEmpty) words.add(word);
    }
    _words = words;
  }

  bool isValid(String word) => _words.contains(word.toUpperCase());

  int get wordCount => _words.length;
}
