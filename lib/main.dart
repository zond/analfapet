import 'dart:convert';
import 'dart:math';
import 'dart:js_interop';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'firebase_options.dart';
import 'models/game_state.dart';
import 'screens/friends_screen.dart';
import 'screens/game_screen.dart';
import 'screens/remote_game_screen.dart';
import 'services/dictionary.dart';
import 'screens/remote_games_screen.dart';
import 'services/friends_service.dart';
import 'services/fcm_service.dart';
import 'services/player_identity.dart';
import 'services/remote_game_controller.dart';
import 'services/remote_game_service.dart';

final playerIdentity = PlayerIdentity();
final fcmService = FcmService();
late final RemoteGameController remoteGameController;
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final navigatorKey = GlobalKey<NavigatorState>();
late final Dictionary dictionary;

void _showToast(String message) {
  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await playerIdentity.init();
  await fcmService.init(playerIdentity.uuid, playerIdentity.secret);

  dictionary = Dictionary();
  await dictionary.load();

  remoteGameController = RemoteGameController(
    fcm: fcmService,
    storage: RemoteGameService(),
    myId: playerIdentity.uuid,
    identity: playerIdentity,
  );
  await remoteGameController.load();

  // Route incoming FCM messages
  fcmService.onMessageHandler((data) async {
    print('[MSG] Received: ${data['type']}');
    final type = data['type'] as String?;
    final sender = data['senderName'] as String? ?? 'Someone';

    if (type == 'friendRequest') {
      await _handleFriendRequest(data);
      _showToast('$sender added you as a friend');
    } else {
      final toast = await remoteGameController.handleMessage(data);
      if (toast != null) _showToast(toast);
    }
  });

  // Listen for notification clicks from service worker
  web.window.navigator.serviceWorker.addEventListener(
    'message',
    ((web.MessageEvent event) {
      final jsData = event.data;
      if (jsData == null) return;
      final map = (jsData as JSObject).dartify();
      if (map is! Map) return;
      final type = map['type'];
      if (type == 'notification-click') {
        final data = (map['data'] as Map).cast<String, dynamic>();
        _handleNotificationClick(data);
      }
    }).toJS,
  );

  runApp(const AnalfapetApp());

  // Check URL fragment for notification data (when app opened from notification click)
  _checkUrlFragment();
}

void _checkUrlFragment() {
  final hash = web.window.location.hash;
  if (hash.startsWith('#notification=')) {
    try {
      final encoded = hash.substring('#notification='.length);
      final jsonStr = Uri.decodeComponent(encoded);
      final data = (jsonDecode(jsonStr) as Map).cast<String, dynamic>();
      print('[Notification] Opened from URL fragment: ${data['type']}');
      // Clear the fragment so it doesn't trigger again on refresh
      web.window.history.replaceState(''.toJS, '', web.window.location.pathname);
      // Delay slightly to let the navigator initialize
      Future.delayed(const Duration(milliseconds: 500), () {
        _handleNotificationClick(data);
      });
    } catch (e) {
      print('[Notification] Failed to parse URL fragment: $e');
    }
  }
}

Future<void> _handleFriendRequest(Map<String, dynamic> data) async {
  final senderId = data['senderId'] as String;
  final senderName = data['senderName'] as String;
  await FriendsService().add(Friend(id: senderId, name: senderName));
  print('[Friends] Auto-added $senderName ($senderId) from friend request');
}

void _handleNotificationClick(Map<String, dynamic> rawData) async {
  // Parse string values back (FCM data is all strings)
  final data = fcmService.parseData(rawData);
  print('[Notification click] type=${data['type']} data=$data');

  final nav = navigatorKey.currentState;
  if (nav == null) return;

  final type = data['type'] as String?;
  final gameId = data['gameId'] as String?;

  // Process the message first (it wasn't handled while the tab was in background)
  try {
    if (type == 'friendRequest') {
      await _handleFriendRequest(data);
    } else {
      await remoteGameController.handleMessage(data);
    }
  } catch (e) {
    print('[Notification click] Error processing: $e');
  }

  switch (type) {
    case 'friendRequest':
      nav.push(MaterialPageRoute(
        builder: (_) => FriendsScreen(
          identity: playerIdentity,
          fcmService: fcmService,
        ),
      ));
    case 'invite' || 'accept' || 'deny':
      nav.push(MaterialPageRoute(
        builder: (_) => RemoteGamesScreen(
          controller: remoteGameController,
          dictionary: dictionary,
          myId: playerIdentity.uuid,
        ),
      ));
    case 'move' || 'hurry' || 'stateSync':
      if (gameId != null) {
        nav.push(MaterialPageRoute(
          builder: (_) => RemoteGameScreen(
            gameId: gameId,
            controller: remoteGameController,
            dictionary: dictionary,
            myId: playerIdentity.uuid,
          ),
        ));
      }
  }
}

class AnalfapetApp extends StatelessWidget {
  const AnalfapetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _openLocalGame(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PlayerCountScreen(dictionary: dictionary),
      ),
    );
  }

  void _openRemoteGames(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RemoteGamesScreen(
          controller: remoteGameController,
          dictionary: dictionary,
          myId: playerIdentity.uuid,
        ),
      ),
    );
  }

  void _openFriends(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FriendsScreen(
        identity: playerIdentity,
        fcmService: fcmService,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      body: Center(
        child: Column(
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
                        '${dictionary.wordCount} ord',
                        style: const TextStyle(color: Colors.white54),
                      ),
                      const SizedBox(height: 48),
                      _MenuButton(
                        onPressed: () => _openLocalGame(context),
                        icon: Icons.people,
                        label: 'Local game',
                      ),
                      const SizedBox(height: 12),
                      _MenuButton(
                        onPressed: () => _openRemoteGames(context),
                        icon: Icons.wifi,
                        label: 'Remote games',
                      ),
                      const SizedBox(height: 12),
                      _MenuButton(
                        onPressed: () => _openFriends(context),
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
