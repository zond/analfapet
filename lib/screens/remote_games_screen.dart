import 'package:flutter/material.dart';
import '../models/game_state.dart';
import '../models/remote_game.dart';
import '../services/friends_service.dart';
import '../services/remote_game_controller.dart';
import '../services/dictionary.dart';
import '../services/toast.dart';
import 'remote_game_screen.dart';

class RemoteGamesScreen extends StatefulWidget {
  final RemoteGameController controller;
  final Dictionary dictionary;
  final String myId;

  const RemoteGamesScreen({
    super.key,
    required this.controller,
    required this.dictionary,
    required this.myId,
  });

  @override
  State<RemoteGamesScreen> createState() => _RemoteGamesScreenState();
}

class _RemoteGamesScreenState extends State<RemoteGamesScreen> {
  RemoteGameController get ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    ctrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    ctrl.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _newGame() async {
    final friendsService = FriendsService();
    final friends = await friendsService.load();

    if (friends.isEmpty) {
      if (mounted) {
        showToast('Add friends first');
      }
      return;
    }

    final selected = <Friend>{};

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New remote game'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: friends.length,
              itemBuilder: (context, i) {
                final friend = friends[i];
                final isSelected = selected.contains(friend);
                return CheckboxListTile(
                  title: Text(friend.name),
                  subtitle: Text(friend.id, style: const TextStyle(fontSize: 11)),
                  value: isSelected,
                  onChanged: (v) {
                    setDialogState(() {
                      if (v == true) {
                        selected.add(friend);
                      } else {
                        selected.remove(friend);
                      }
                    });
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: selected.isEmpty ? null : () => Navigator.pop(context, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && selected.isNotEmpty) {
      await ctrl.createGame(selected.toList());
      if (mounted) {
        showToast('Game created, invites sent');
      }
    }
  }

  void _openGame(RemoteGame game) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RemoteGameScreen(
          gameId: game.gameId,
          controller: ctrl,
          dictionary: widget.dictionary,
          myId: widget.myId,
        ),
      ),
    );
  }

  void _acceptInvite(RemoteGame game) async {
    await ctrl.acceptInvite(game.gameId);
    if (mounted) {
      showToast('Accepted');
    }
  }

  void _denyInvite(RemoteGame game) async {
    await ctrl.denyInvite(game.gameId);
  }

  void _deleteGame(RemoteGame game) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete game'),
        content: Text('Delete game with ${_gameSubtitle(game)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await ctrl.deleteGame(game.gameId);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _gameSubtitle(RemoteGame game) {
    final names = game.players.map((p) => p.uuid == widget.myId ? 'You' : p.name).join(', ');
    return names;
  }

  String _gameStatus(RemoteGame game) {
    switch (game.status) {
      case RemoteGameStatus.invited:
        return 'Invited by ${game.players.firstWhere((p) => p.uuid == game.creatorId).name}';
      case RemoteGameStatus.accepted:
        final waiting = game.players.where((p) => !p.accepted).map((p) => p.name);
        return 'Waiting for ${waiting.join(", ")}';
      case RemoteGameStatus.active:
        if (!game.allAccepted) {
          final waiting = game.players.where((p) => !p.accepted).map((p) => p.name);
          return 'Waiting for ${waiting.join(", ")}';
        }
        final state = GameState.replayFromMoves(
          gameId: game.gameId,
          playerCount: game.players.length,
          seed: game.seed,
          moves: game.moves,
        );
        if (state.gameOver) {
          return 'Finished — ${game.moves.length} moves';
        }
        final currentPlayer = game.players[state.currentPlayer];
        final turnName = currentPlayer.uuid == widget.myId ? 'Your' : "${currentPlayer.name}'s";
        return "$turnName turn — ${game.moves.length} moves";
      case RemoteGameStatus.finished:
        return 'Finished — ${game.moves.length} moves';
    }
  }

  @override
  Widget build(BuildContext context) {
    final invitations = ctrl.invitations;
    final allActive = ctrl.activeGames;
    final active = allActive.where((g) => !ctrl.isGameOverViaGameplay(g)).toList();
    final finishedViaGameplay = allActive.where((g) => ctrl.isGameOverViaGameplay(g)).toList();
    final finished = [...ctrl.finishedGames, ...finishedViaGameplay];

    return Scaffold(
      backgroundColor: const Color(0xFF8B4513),
      appBar: AppBar(
        title: const Text('Remote games'),
        backgroundColor: const Color(0xFF6D3410),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _newGame,
        backgroundColor: const Color(0xFF4CAF50),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        children: [
          if (invitations.isNotEmpty) ...[
            _sectionHeader('Invitations'),
            ...invitations.map((g) => _invitationTile(g)),
          ],
          if (active.isNotEmpty) ...[
            _sectionHeader('Active'),
            ...active.map((g) => _gameTile(g)),
          ],
          if (finished.isNotEmpty) ...[
            _sectionHeader('Finished'),
            ...finished.map((g) => _gameTile(g)),
          ],
          if (invitations.isEmpty && active.isEmpty && finished.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No remote games yet.\nTap + to start one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _invitationTile(RemoteGame game) {
    return Dismissible(
      key: Key(game.gameId),
      onDismissed: (_) => _deleteGame(game),
      background: Container(color: Colors.red),
      child: ListTile(
        title: Text(_gameSubtitle(game), style: const TextStyle(color: Colors.white)),
        subtitle: Text(_gameStatus(game), style: const TextStyle(color: Colors.white54, fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check, color: Colors.greenAccent),
              onPressed: () => _acceptInvite(game),
              tooltip: 'Accept',
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.redAccent),
              onPressed: () => _denyInvite(game),
              tooltip: 'Deny',
            ),
          ],
        ),
      ),
    );
  }

  Widget _gameTile(RemoteGame game) {
    return ListTile(
      title: Text(_gameSubtitle(game), style: const TextStyle(color: Colors.white)),
      subtitle: Text(_gameStatus(game), style: const TextStyle(color: Colors.white54, fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white38),
            onPressed: () => _deleteGame(game),
          ),
          const Icon(Icons.chevron_right, color: Colors.white38),
        ],
      ),
      onTap: () => _openGame(game),
    );
  }
}
