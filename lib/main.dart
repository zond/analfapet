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
import 'services/message_codec.dart';
import 'services/player_identity.dart';
import 'services/remote_game_controller.dart';
import 'services/remote_game_service.dart';
import 'services/toast.dart';

final playerIdentity = PlayerIdentity();
final fcmService = FcmService();
late final RemoteGameController remoteGameController;
final navigatorKey = GlobalKey<NavigatorState>();
late final Dictionary dictionary;

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
    dictionary: dictionary,
  );
  await remoteGameController.load();

  // Route incoming FCM messages
  fcmService.onMessageHandler((data) async {
    final base64Data = data['d'] as String?;
    if (base64Data == null) {
      print('[MSG] Received message without binary data, ignoring');
      return;
    }

    try {
      final decoded = MessageCodec.decode(base64Data);
      final msgType = decoded['type'] as String;
      print('[MSG] Received: $msgType');

      if (msgType == 'friend') {
        final uuid = decoded['uuid'] as String;
        final name = decoded['name'] as String;
        await FriendsService().add(Friend(id: uuid, name: name));
        print('[Friends] Auto-added $name ($uuid) from friend request');
        showToast('$name added you as a friend');
      } else if (msgType == 'game') {
        final toast = await remoteGameController.handleGameMessage(decoded);
        if (toast != null) showToast(toast);
      }
    } catch (e) {
      print('[MSG] Failed to decode message: $e');
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
      } else if (type == 'sw-updated') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showToast('New version available — reload to update');
        });
      }
    }).toJS,
  );

  // Fetch inbox when tab gains focus or internet returns
  web.document.addEventListener(
    'visibilitychange',
    ((web.Event _) {
      if (web.document.visibilityState == 'visible') {
        _fetchInbox();
      }
    }).toJS,
  );
  web.window.addEventListener('online', ((web.Event _) { _fetchInbox(); }).toJS);

  runApp(const AnalfapetApp());
  initToast(navigatorKey);

  // Check URL fragment for notification data (when app opened from notification click)
  _checkUrlFragment();

  // Also fetch inbox on startup
  _fetchInbox();
}

DateTime? _lastInboxFetch;

Future<void> _fetchInbox() async {
  final now = DateTime.now();
  if (_lastInboxFetch != null && now.difference(_lastInboxFetch!) < const Duration(seconds: 5)) {
    return;
  }
  _lastInboxFetch = now;

  final messages = await fcmService.fetchInbox(
    playerIdentity.uuid,
    playerIdentity.secret,
  );
  if (messages.isEmpty) return;
  print('[Inbox] Fetched ${messages.length} messages');
  for (final data in messages) {
    final base64Data = data['d'];
    if (base64Data == null) continue;
    try {
      final decoded = MessageCodec.decode(base64Data);
      final msgType = decoded['type'] as String;
      print('[Inbox] Processing: $msgType');
      if (msgType == 'friend') {
        final uuid = decoded['uuid'] as String;
        final name = decoded['name'] as String;
        await FriendsService().add(Friend(id: uuid, name: name));
      } else if (msgType == 'game') {
        await remoteGameController.handleGameMessage(decoded);
      }
    } catch (e) {
      print('[Inbox] Failed to process message: $e');
    }
  }
}

void _checkUrlFragment() {
  final hash = web.window.location.hash;
  if (hash.startsWith('#notification=')) {
    try {
      final encoded = hash.substring('#notification='.length);
      final jsonStr = Uri.decodeComponent(encoded);
      final data = (jsonDecode(jsonStr) as Map).cast<String, dynamic>();
      print('[Notification] Opened from URL fragment');
      web.window.history.replaceState(''.toJS, '', web.window.location.pathname);
      _waitForNavigatorAndHandle(data);
    } catch (e) {
      print('[Notification] Failed to parse URL fragment: $e');
    }
  } else if (hash.startsWith('#friend=')) {
    try {
      final encoded = hash.substring('#friend='.length);
      final jsonStr = Uri.decodeComponent(encoded);
      final data = (jsonDecode(jsonStr) as Map).cast<String, dynamic>();
      final id = data['id'] as String?;
      final name = data['name'] as String?;
      print('[Friend link] id=$id name=$name');
      web.window.history.replaceState(''.toJS, '', web.window.location.pathname);
      if (id != null && id != playerIdentity.uuid) {
        _waitForNavigatorThen(() => _handleFriendLink(id, name));
      }
    } catch (e) {
      print('[Friend link] Failed to parse URL fragment: $e');
    }
  }
}

Future<void> _waitForNavigatorAndHandle(Map<String, dynamic> data) async {
  await _waitForNavigatorThen(() => _handleNotificationClick(data));
}

Future<void> _waitForNavigatorThen(void Function() action) async {
  for (var i = 0; i < 50; i++) {
    if (navigatorKey.currentState != null) {
      action();
      return;
    }
    await Future.delayed(const Duration(milliseconds: 100));
  }
  print('[Nav] Navigator not ready after 5 seconds, giving up');
}

void _handleFriendLink(String id, String? name) async {
  final nav = navigatorKey.currentState;
  if (nav == null) return;

  // Ensure we have a name before sending the friend request back
  if (!playerIdentity.hasName) {
    final context = nav.context;
    final controller = TextEditingController();
    final chosenName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('What\'s your name?'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Your name'),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final v = controller.text.trim();
              Navigator.pop(context, v.isNotEmpty ? v : 'Anon');
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    await playerIdentity.setName((chosenName != null && chosenName.isNotEmpty) ? chosenName : 'Anon');
  }

  if (name != null && name.isNotEmpty) {
    // Auto-add and navigate to friends screen
    await FriendsService().add(Friend(id: id, name: name));
    await FriendsService().sendFriendRequest(
      fcmService, playerIdentity.uuid, playerIdentity.name ?? 'Anon', id,
    );
    showToast('Added $name as a friend');
    nav.pushAndRemoveUntil(MaterialPageRoute(
      builder: (_) => FriendsScreen(
        identity: playerIdentity,
        fcmService: fcmService,
      ),
    ), (r) => r.isFirst);
  } else {
    nav.pushAndRemoveUntil(MaterialPageRoute(
      builder: (_) => FriendsScreen(
        identity: playerIdentity,
        fcmService: fcmService,
      ),
    ), (r) => r.isFirst);
  }
}

void _handleNotificationClick(Map<String, dynamic> rawData) async {
  print('[Notification click] data=$rawData');

  final nav = navigatorKey.currentState;
  if (nav == null) return;

  // Decode the binary payload if present
  final base64Data = rawData['d'] as String?;
  if (base64Data == null) {
    print('[Notification click] No binary data, ignoring');
    return;
  }

  try {
    final decoded = MessageCodec.decode(base64Data);
    final msgType = decoded['type'] as String;

    // Process the message first (it wasn't handled while the tab was in background)
    if (msgType == 'friend') {
      final uuid = decoded['uuid'] as String;
      final name = decoded['name'] as String;
      await FriendsService().add(Friend(id: uuid, name: name));
      nav.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => FriendsScreen(
            identity: playerIdentity,
            fcmService: fcmService,
          ),
        ),
        (r) => r.isFirst,
      );
    } else if (msgType == 'game') {
      await remoteGameController.handleGameMessage(decoded);
      final gameId = decoded['gameId'] as String;
      nav.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => RemoteGameScreen(
            gameId: gameId,
            controller: remoteGameController,
            dictionary: dictionary,
            myId: playerIdentity.uuid,
          ),
        ),
        (r) => r.isFirst,
      );
    }
  } catch (e) {
    print('[Notification click] Error processing: $e');
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
        colorSchemeSeed: const Color(0xFF6D3410),
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}

bool _shouldShowInstallHint() {
  final isStandalone = web.window.matchMedia('(display-mode: standalone)').matches;
  if (isStandalone) return false;
  final ua = web.window.navigator.userAgent.toLowerCase();
  final isMobile = ua.contains('android') || ua.contains('iphone') || ua.contains('ipad');
  // iPadOS 13+ reports as Macintosh — detect via touch support
  final isIPadOS = ua.contains('macintosh') && web.window.navigator.maxTouchPoints > 0;
  return isMobile || isIPadOS;
}

void _triggerInstall() {
  final prompt = _jsGetDeferredPrompt;
  if (prompt != null) {
    _jsPrompt(prompt);
    _jsSetDeferredPrompt = null;
  }
}

bool get _canPromptInstall => _jsGetDeferredPrompt != null;

@JS('window._deferredInstallPrompt')
external JSObject? get _jsGetDeferredPrompt;

@JS('window._deferredInstallPrompt')
external set _jsSetDeferredPrompt(JSObject? value);

@JS()
@staticInterop
class _PromptEvent {}

extension on _PromptEvent {
  external void prompt();
}

void _jsPrompt(JSObject obj) => (obj as _PromptEvent).prompt();

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
      backgroundColor: const Color(0xFF8B4513),
      body: Center(
        child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(
                            '(an-)',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 4,
                            ),
                          ),
                          Text(
                            'ALFAPET',
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 8,
                            ),
                          ),
                        ],
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
                      if (_shouldShowInstallHint()) ...[
                        const SizedBox(height: 32),
                        GestureDetector(
                          onTap: _canPromptInstall ? _triggerInstall : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.install_mobile,
                                    color: _canPromptInstall ? Colors.white70 : Colors.white54,
                                    size: 18),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _canPromptInstall
                                        ? 'Tap to install for better notifications'
                                        : 'Add to home screen for better notifications',
                                    style: TextStyle(
                                      color: _canPromptInstall ? Colors.white70 : Colors.white54,
                                      fontSize: 13,
                                      decoration: _canPromptInstall ? TextDecoration.underline : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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
      backgroundColor: const Color(0xFF8B4513),
      appBar: AppBar(
        title: const Text('Local game'),
        backgroundColor: const Color(0xFF6D3410),
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
