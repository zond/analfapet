import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'models/game_state.dart';
import 'screens/game_screen.dart';
import 'services/dictionary.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const AnalfapetApp());
}

class AnalfapetApp extends StatelessWidget {
  const AnalfapetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Analfapet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D32),
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Dictionary? _dictionary;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDictionary();
  }

  Future<void> _loadDictionary() async {
    try {
      final dict = Dictionary();
      await dict.load();
      setState(() {
        _dictionary = dict;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load dictionary: $e';
        _loading = false;
      });
    }
  }

  void _startLocalGame() {
    final seed = Random().nextInt(0xFFFFFFFF);
    final game = GameState.newGame(
      gameId: 'local-${DateTime.now().millisecondsSinceEpoch}',
      localPlayerId: 'player1',
      remotePlayerId: 'player2',
      seed: seed,
      localGoesFirst: true,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(gameState: game, dictionary: _dictionary!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      body: Center(
        child: _loading
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.greenAccent),
                  SizedBox(height: 16),
                  Text('Loading dictionary...', style: TextStyle(color: Colors.white70)),
                ],
              )
            : _error != null
                ? Text(_error!, style: const TextStyle(color: Colors.redAccent))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'ANALFAPET',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_dictionary!.wordCount} ord',
                        style: const TextStyle(color: Colors.white54),
                      ),
                      const SizedBox(height: 48),
                      ElevatedButton.icon(
                        onPressed: _startLocalGame,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Local game'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          textStyle: const TextStyle(fontSize: 18),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: null, // TODO: implement online play
                        icon: const Icon(Icons.wifi),
                        label: const Text('Online game'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          textStyle: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
