import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/friends_service.dart';
import 'qr_scanner_screen.dart';

class FriendsScreen extends StatefulWidget {
  final String playerId;

  const FriendsScreen({super.key, required this.playerId});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _friendsService = FriendsService();
  List<Friend> _friends = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final friends = await _friendsService.load();
    setState(() {
      _friends = friends;
      _loading = false;
    });
  }

  void _showMyQR() {
    final data = jsonEncode({'id': widget.playerId});
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
            SelectableText(
              widget.playerId,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.playerId));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ID copied')),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy ID'),
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

    // Try to parse as JSON with id field, or use raw string as id
    String? id;
    try {
      final parsed = jsonDecode(result) as Map<String, dynamic>;
      id = parsed['id'] as String?;
    } catch (_) {
      id = result.trim();
    }

    if (id == null || id.isEmpty) return;
    if (id == widget.playerId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("That's your own ID")),
        );
      }
      return;
    }

    _showAddFriendDialog(id);
  }

  void _addManually() {
    final nameController = TextEditingController();
    final idController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add friend manually'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: idController,
              decoration: const InputDecoration(labelText: 'Player ID'),
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
              final id = idController.text.trim();
              if (name.isNotEmpty && id.isNotEmpty) {
                await _friendsService.add(Friend(id: id, name: name));
                await _load();
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
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
                await _friendsService.add(Friend(id: id, name: name));
                await _load();
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
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: const Text('Friends'),
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
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _addManually,
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Add manually'),
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
