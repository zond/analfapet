import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/fcm_service.dart';
import '../services/friends_service.dart';
import '../services/player_identity.dart';
import 'qr_scanner_screen.dart';

class FriendsScreen extends StatefulWidget {
  final PlayerIdentity identity;
  final FcmService fcmService;

  const FriendsScreen({
    super.key,
    required this.identity,
    required this.fcmService,
  });

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _friendsService = FriendsService();
  List<Friend> _friends = [];
  bool _loading = true;

  PlayerIdentity get _identity => widget.identity;

  Future<void> _addAndNotify(Friend friend) async {
    await _friendsService.add(friend);
    await _friendsService.sendFriendRequest(
      widget.fcmService, _identity.uuid, _identity.name ?? 'Anon', friend.id,
    );
    await _load();
  }

  @override
  void initState() {
    super.initState();
    _friendsService.addListener(_load);
    _init();
  }

  @override
  void dispose() {
    _friendsService.removeListener(_load);
    super.dispose();
  }

  Future<void> _init() async {
    await _load();
    if (!_identity.hasName && mounted) {
      await _promptForName();
    }
  }

  Future<void> _load() async {
    final friends = await _friendsService.load();
    setState(() {
      _friends = friends;
      _loading = false;
    });
  }

  Future<void> _promptForName() async {
    final controller = TextEditingController(text: _identity.name ?? '');
    final name = await showDialog<String>(
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
              if (v.isNotEmpty) Navigator.pop(context, v);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    await _identity.setName((name != null && name.isNotEmpty) ? name : 'Anon');
    setState(() {});
  }

  void _editName() async {
    await _promptForName();
  }

  String get _friendLink {
    final encoded = Uri.encodeComponent(jsonEncode({'id': _identity.uuid, 'name': _identity.name}));
    // Use the current origin + base path
    final base = Uri.base.toString().replaceAll(RegExp(r'#.*$'), '');
    return '$base#friend=$encoded';
  }

  void _showMyQR() {
    final data = jsonEncode({'id': _identity.uuid, 'name': _identity.name});
    final link = _friendLink;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your QR code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 200,
              height: 200,
              child: QrImageView(
                data: data,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    link,
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy link',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: link));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanQR() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (result == null || !mounted) return;

    String? id;
    String? name;
    try {
      final parsed = jsonDecode(result) as Map<String, dynamic>;
      id = parsed['id'] as String?;
      name = parsed['name'] as String?;
    } catch (_) {
      id = result.trim();
    }

    if (id == null || id.isEmpty) return;
    if (id == _identity.uuid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("That's your own ID")),
        );
      }
      return;
    }

    if (name != null && name.isNotEmpty) {
      await _addAndNotify(Friend(id: id, name: name));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $name')),
        );
      }
    } else {
      _showAddFriendDialog(id);
    }
  }

  void _showAddFriendDialog(String id) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add friend'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ID: $id', style: const TextStyle(fontSize: 12, color: Colors.white54)),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                await _addAndNotify(Friend(id: id, name: name));
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _removeFriend(Friend friend) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove friend'),
        content: Text('Remove ${friend.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _friendsService.remove(friend.id);
              await _load();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _identity.hasName ? 'Friends of ${_identity.name}' : 'Friends';

    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: GestureDetector(
          onTap: _editName,
          child: Text(title),
        ),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _showMyQR,
            icon: const Icon(Icons.qr_code),
            tooltip: 'My QR code',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
          : _friends.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'No friends yet.',
                        style: TextStyle(color: Colors.white54, fontSize: 16),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _showMyQR,
                        icon: const Icon(Icons.qr_code),
                        label: const Text('Show my QR'),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _scanQR,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan QR code'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _friends.length,
                  itemBuilder: (context, index) {
                    final friend = _friends[index];
                    return ListTile(
                      leading: const Icon(Icons.person, color: Colors.white70),
                      title: Text(friend.name, style: const TextStyle(color: Colors.white)),
                      subtitle: Text(friend.id,
                          style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.white38),
                        onPressed: () => _removeFriend(friend),
                      ),
                    );
                  },
                ),
      floatingActionButton: _friends.isNotEmpty
          ? FloatingActionButton(
              onPressed: _scanQR,
              backgroundColor: const Color(0xFF4CAF50),
              child: const Icon(Icons.qr_code_scanner),
            )
          : null,
    );
  }
}
