import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'models/game_state.dart';
import 'screens/friends_screen.dart';
import 'screens/game_screen.dart';
import 'services/dictionary.dart';
import 'services/player_identity.dart';

final playerIdentity = PlayerIdentity();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await playerIdentity.init();
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

  void _openLocalGame() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PlayerCountScreen(dictionary: _dictionary!),
      ),
    );
  }

  void _openFriends() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FriendsScreen(playerId: playerIdentity.uuid)),
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
                      _MenuButton(
                        onPressed: _openLocalGame,
                        icon: Icons.people,
                        label: 'Local game',
                      ),
                      const SizedBox(height: 12),
                      _MenuButton(
                        onPressed: null, // TODO: implement
                        icon: Icons.wifi,
                        label: 'Remote game',
                      ),
                      const SizedBox(height: 12),
                      _MenuButton(
                        onPressed: _openFriends,
                        icon: Icons.group,
                        label: 'Friends',
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  const _MenuButton({required this.onPressed, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        textStyle: const TextStyle(fontSize: 18),
        minimumSize: const Size(220, 0),
      ),
    );
  }
}

class _PlayerCountScreen extends StatelessWidget {
  final Dictionary dictionary;

  const _PlayerCountScreen({required this.dictionary});

  void _start(BuildContext context, int playerCount) {
    final seed = Random().nextInt(0xFFFFFFFF);
    final game = GameState.newGame(
      gameId: 'local-${DateTime.now().millisecondsSinceEpoch}',
      playerCount: playerCount,
      seed: seed,
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(gameState: game, dictionary: dictionary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: const Text('Local game'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'How many players?',
              style: TextStyle(color: Colors.white70, fontSize: 20),
            ),
            const SizedBox(height: 32),
            for (var n = 2; n <= 4; n++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ElevatedButton(
                  onPressed: () => _start(context, n),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                    textStyle: const TextStyle(fontSize: 18),
                    minimumSize: const Size(220, 0),
                  ),
                  child: Text('$n players'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
