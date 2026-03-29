import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

class Dictionary {
  late final Set<String> _words;

  Future<void> load() async {
    final data = await rootBundle.load('assets/wordlist.txt.gz');
    final bytes = data.buffer.asUint8List();
    final decompressed = gzip.decode(bytes);
    final text = utf8.decode(decompressed);
    _words = text
        .split('\n')
        .map((w) => w.trim().toUpperCase())
        .where((w) => w.isNotEmpty)
        .toSet();
  }

  bool isValid(String word) => _words.contains(word.toUpperCase());

  int get wordCount => _words.length;
}
