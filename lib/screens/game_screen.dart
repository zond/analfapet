import 'package:flutter/material.dart';
import '../models/board.dart';
import '../models/game_state.dart';
import '../models/move.dart';
import '../models/tile.dart';
import '../services/dictionary.dart';
import '../services/move_validator.dart';
import '../services/toast.dart';
import '../widgets/board_widget.dart';
import '../widgets/tile_rack_widget.dart';

class GameScreen extends StatefulWidget {
  final GameState gameState;
  final Dictionary dictionary;

  // Remote mode (null = local mode)
  final int? localPlayerIndex;
  final List<String>? playerNames;
  final Future<void> Function(Move move)? onMoveSubmitted;
  final VoidCallback? onHurry;

  /// Last move played (for highlighting and info display)
  final Move? lastMove;
  /// Who played the last move
  final int? lastMovePlayerIndex;

  const GameScreen({
    super.key,
    required this.gameState,
    required this.dictionary,
    this.localPlayerIndex,
    this.playerNames,
    this.onMoveSubmitted,
    this.onHurry,
    this.lastMove,
    this.lastMovePlayerIndex,
  });

  bool get isRemote => localPlayerIndex != null;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final List<TilePlacement> _pendingPlacements = [];
  late final MoveValidator _validator;
  bool _handover = false;
  Move? _lastLocalMove;
  int? _lastLocalMovePlayer;

  // Drag state
  Tile? _dragTile;
  int? _dragFromRackIndex;
  Offset _dragPosition = Offset.zero;

  // User's rack arrangement (may differ from GameState order)
  List<Tile>? _userRackOrder;

  // Hit testing
  final GlobalKey _boardKey = GlobalKey();
  final GlobalKey _rackKey = GlobalKey();

  GameState get game => widget.gameState;
  bool get isRemote => widget.isRemote;
  bool get isMyTurn => isRemote
      ? game.currentPlayer == widget.localPlayerIndex
      : true;

  /// The underlying GameState rack (live reference).
  List<Tile> get _gameRack => isRemote
      ? game.racks[widget.localPlayerIndex!]
      : game.currentRack;

  /// The rack as displayed to the user (preserves their arrangement).
  List<Tile> get _myRack => _userRackOrder ?? _gameRack;

  Move? get _lastMove => isRemote ? widget.lastMove : _lastLocalMove;
  int? get _lastMovePlayer => isRemote ? widget.lastMovePlayerIndex : _lastLocalMovePlayer;

  String _playerName(int index) {
    if (widget.playerNames != null && index < widget.playerNames!.length) {
      return widget.playerNames![index];
    }
    return 'Player ${index + 1}';
  }

  @override
  void initState() {
    super.initState();
    _validator = MoveValidator(widget.dictionary);
    _syncRackWithPending();
  }

  @override
  void didUpdateWidget(covariant GameScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.gameState, oldWidget.gameState)) {
      _dragTile = null;
      _syncRackWithPending();
    }
  }

  /// Ensure the rack and pending placements are consistent with the current GameState.
  /// Preserves the user's tile arrangement as much as possible.
  void _syncRackWithPending() {
    final freshRack = List<Tile>.from(_gameRack);

    // Check which pending placements are still valid
    final stillValid = <TilePlacement>[];
    for (final p in _pendingPlacements) {
      if (widget.gameState.board.isEmpty(p.row, p.col)) {
        final rackIdx = freshRack.indexWhere((t) => t == p.placedTile.tile);
        if (rackIdx >= 0) {
          freshRack.removeAt(rackIdx);
          stillValid.add(p);
        }
      }
    }

    // freshRack now has the tiles that should be visible in the rack.
    // Preserve the user's previous arrangement order.
    final previousOrder = _userRackOrder;
    if (previousOrder != null) {
      final remaining = List<Tile>.from(freshRack);
      final ordered = <Tile>[];
      // Keep tiles from previous order that still exist
      for (final tile in previousOrder) {
        final idx = remaining.indexWhere((t) => t == tile);
        if (idx >= 0) {
          ordered.add(remaining.removeAt(idx));
        }
      }
      // Append any new tiles at the end
      ordered.addAll(remaining);
      _userRackOrder = ordered;
    } else {
      _userRackOrder = freshRack;
    }

    // Also update the GameState rack to match (for applyMove etc.)
    _gameRack
      ..clear()
      ..addAll(_userRackOrder!);

    _pendingPlacements
      ..clear()
      ..addAll(stillValid);
  }

  // --- Drag handling ---

  void _onRackTileDragStart(int index, Offset globalPosition) {
    setState(() {
      _dragTile = _myRack[index];
      _dragFromRackIndex = index;
      _dragPosition = globalPosition;
      _myRack.removeAt(index);
      _userRackOrder = List.from(_myRack);
    });
  }

  void _onBoardTileDragStart(int row, int col, Offset globalPosition) {
    final idx = _pendingPlacements.indexWhere((p) => p.row == row && p.col == col);
    if (idx < 0) return;
    setState(() {
      final removed = _pendingPlacements.removeAt(idx);
      _dragTile = removed.placedTile.tile;
      _dragFromRackIndex = null;
      _dragPosition = globalPosition;
    });
  }

  int? _rackHoverIndex;

  void _onDragUpdate(Offset globalPosition) {
    setState(() {
      _dragPosition = globalPosition;
      _rackHoverIndex = _isOverRack(globalPosition) ? _rackInsertIndex(globalPosition) : null;
    });
  }

  void _onDragEnd() {
    if (_dragTile == null) return;
    _rackHoverIndex = null;

    final boardBox = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (boardBox != null) {
      final local = boardBox.globalToLocal(_dragPosition);
      final boardSize = boardBox.size.width;
      if (local.dx >= 0 && local.dx < boardSize && local.dy >= 0 && local.dy < boardSize) {
        var (row, col) = BoardWidget.positionToCell(local, boardSize);

        // If target cell is occupied, find the nearest empty cell
        if (!_isCellFree(row, col)) {
          final nearest = _findNearestFreeCell(row, col);
          if (nearest != null) {
            (row, col) = nearest;
          } else {
            // No free cell nearby — fall through to rack return
            row = -1;
          }
        }

        if (row >= 0 && _isCellFree(row, col)) {
          if (_dragTile!.letter == '*') {
            final tile = _dragTile!;
            setState(() {
              _dragTile = null;
            });
            _showBlankLetterPicker(row, col, tile);
            return;
          }
          setState(() {
            _pendingPlacements.add(TilePlacement(row, col, PlacedTile(_dragTile!)));
            _dragTile = null;
          });
          return;
        }
      }
    }

    // Not dropped on the board — return to rack at the right position
    setState(() {
      final insertAt = _rackInsertIndex(_dragPosition);
      _myRack.insert(insertAt, _dragTile!);
      _userRackOrder = List.from(_myRack);
      _dragTile = null;
      _dragFromRackIndex = null;
    });
  }

  bool _isCellFree(int row, int col) =>
      game.board.isEmpty(row, col) && !_pendingPlacements.any((p) => p.row == row && p.col == col);

  /// Find the nearest free cell using a spiral search from (row, col).
  (int, int)? _findNearestFreeCell(int row, int col) {
    for (var dist = 1; dist <= 3; dist++) {
      for (var dr = -dist; dr <= dist; dr++) {
        for (var dc = -dist; dc <= dist; dc++) {
          if (dr.abs() != dist && dc.abs() != dist) continue; // only check the ring
          final r = row + dr, c = col + dc;
          if (r >= 0 && r < Board.size && c >= 0 && c < Board.size && _isCellFree(r, c)) {
            return (r, c);
          }
        }
      }
    }
    return null;
  }

  /// Calculate rack insert index from a global drop position.
  bool _isOverRack(Offset globalPosition) {
    final rackBox = _rackKey.currentContext?.findRenderObject() as RenderBox?;
    if (rackBox == null) return false;
    final local = rackBox.globalToLocal(globalPosition);
    return local.dx >= 0 && local.dx < rackBox.size.width &&
           local.dy >= -20 && local.dy < rackBox.size.height + 20; // generous vertical tolerance
  }

  int _rackInsertIndex(Offset globalPosition) {
    final rackBox = _rackKey.currentContext?.findRenderObject() as RenderBox?;
    if (rackBox == null) return _myRack.length;
    final local = rackBox.globalToLocal(globalPosition);
    final tileWidth = 48.0; // tile width (44) + margin (4)
    final rackStartX = (rackBox.size.width - _myRack.length * tileWidth) / 2;
    final relativeX = local.dx - rackStartX;
    final index = (relativeX / tileWidth).floor();
    return index.clamp(0, _myRack.length);
  }

  void _onCellTap(int row, int col) {
    final existingIndex = _pendingPlacements.indexWhere((p) => p.row == row && p.col == col);
    if (existingIndex >= 0) {
      setState(() {
        final removed = _pendingPlacements.removeAt(existingIndex);
        _myRack.add(removed.placedTile.tile);
        _userRackOrder = List.from(_myRack);
      });
    }
  }

  void _showBlankLetterPicker(int row, int col, Tile tile) {
    showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose letter'),
        content: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: 'ABCDEFGHIJKLMNOPRSTUVXYZÅÄÖ'.split('').map((letter) {
            return InkWell(
              onTap: () => Navigator.pop(context, letter),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8D5B7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(letter,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF3E2723))),
              ),
            );
          }).toList(),
        ),
      ),
    ).then((letter) {
      if (letter != null) {
        setState(() {
          _pendingPlacements.add(
            TilePlacement(row, col, PlacedTile(tile, blankLetter: letter)),
          );
        });
      } else {
        setState(() {
          _myRack.add(tile);
          _userRackOrder = List.from(_myRack);
        });
      }
    });
  }

  Board get _boardWithPending {
    final tempBoard = Board.from(game.board);
    for (final p in _pendingPlacements) {
      tempBoard.set(p.row, p.col, p.placedTile);
    }
    return tempBoard;
  }

  void _submitMove() {
    final isFirstMove = game.board.isEmptyBoard;
    final result = _validator.validate(game.board, _pendingPlacements, isFirstMove);

    if (!result.valid) {
      showToast(result.error!);
      return;
    }

    final move = Move(
      type: MoveType.play,
      turnSeqNr: game.turnSeqNr,
      boardHash: game.board.computeHash(),
      placements: List.of(_pendingPlacements),
      score: result.score,
    );

    if (isRemote) {
      // Re-add pending tiles to the GameState rack before applyMove
      // (they were removed from _gameRack during drag)
      for (final p in _pendingPlacements) {
        _gameRack.add(p.placedTile.tile);
      }
      game.applyMove(move);
      setState(() {
        _pendingPlacements.clear();
        _userRackOrder = null;
      });

      showToast('${result.wordsFormed.join(", ")} — ${result.score} points!');

      widget.onMoveSubmitted?.call(move);
    } else {
      final player = game.currentPlayer;
      for (final p in _pendingPlacements) {
        game.board.set(p.row, p.col, p.placedTile);
      }
      game.scores[game.currentPlayer] += result.score;
      game.drawTiles(game.currentRack, _pendingPlacements.length);
      game.consecutivePasses = 0;
      if (game.currentRack.isEmpty && game.bag.isEmpty) {
        game.gameOver = true;
      }

      showToast('${result.wordsFormed.join(", ")} — ${result.score} points!');

      setState(() {
        _lastLocalMove = move;
        _lastLocalMovePlayer = player;
        _pendingPlacements.clear();
        if (!game.gameOver) {
          game.nextTurn();
        }
        _userRackOrder = null;
        _handover = !game.gameOver;
      });
    }
  }

  void _pass() {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pass'),
        content: const Text('Are you sure you want to pass your turn?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pass'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed != true) return;
      _doPass();
    });
  }

  void _doPass() {
    _recallTiles();
    final move = Move(
      type: MoveType.pass,
      turnSeqNr: game.turnSeqNr,
      boardHash: game.board.computeHash(),
    );

    if (isRemote) {
      game.applyMove(move);
      setState(() => _pendingPlacements.clear());
      widget.onMoveSubmitted?.call(move);
    } else {
      final player = game.currentPlayer;
      game.consecutivePasses++;
      if (game.consecutivePasses >= game.playerCount * 2) {
        game.gameOver = true;
      }
      setState(() {
        _lastLocalMove = move;
        _lastLocalMovePlayer = player;
        _pendingPlacements.clear();
        if (!game.gameOver) {
          game.nextTurn();
        }
        _userRackOrder = null;
        _handover = !game.gameOver;
      });
    }
  }

  void _swapTiles() {
    _recallTiles();
    // Show dialog to select tiles to swap
    final toSwap = <int>{};
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select tiles to swap'),
          content: Wrap(
            spacing: 4,
            children: List.generate(_myRack.length, (i) {
              final tile = _myRack[i];
              final selected = toSwap.contains(i);
              return GestureDetector(
                onTap: () => setDialogState(() {
                  if (selected) {
                    toSwap.remove(i);
                  } else {
                    toSwap.add(i);
                  }
                }),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFFFD54F) : const Color(0xFFE8D5B7),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: selected ? Colors.orange : const Color(0xFF5D4037),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      tile.letter == '*' ? ' ' : tile.letter,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF3E2723)),
                    ),
                  ),
                ),
              );
            }),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: toSwap.isEmpty ? null : () => Navigator.pop(context, toSwap),
              child: const Text('Swap'),
            ),
          ],
        ),
      ),
    ).then((result) {
      if (result == null || result is! Set<int>) return;
      if (game.bag.length < result.length) {
        showToast('Not enough tiles in the bag');
        return;
      }

      // Collect the letters of tiles to swap
      final swappedLetters = result.map((i) => _myRack[i].letter).toList();

      final move = Move(
        type: MoveType.swap,
        turnSeqNr: game.turnSeqNr,
        boardHash: game.board.computeHash(),
        swappedTileLetters: swappedLetters,
      );

      if (isRemote) {
        game.applyMove(move);
        setState(() {});
        widget.onMoveSubmitted?.call(move);
      } else {
        final player = game.currentPlayer;
        game.applyMove(move);
        setState(() {
          _lastLocalMove = move;
          _lastLocalMovePlayer = player;
          _userRackOrder = null;
          _handover = !game.gameOver;
        });
      }
    });
  }

  void _recallTiles() {
    setState(() {
      _pendingPlacements.clear();
      _syncRackWithPending();
    });
  }

  void _shuffleRack() {
    setState(() {
      _myRack.shuffle();
      _userRackOrder = List.from(_myRack);
    });
  }

  String get _scoreText {
    final parts = <String>[];
    for (var i = 0; i < game.playerCount; i++) {
      parts.add('${_playerName(i)}: ${game.scores[i]}');
    }
    return parts.join('  ');
  }

  String get _turnLabel {
    if (game.gameOver) {
      int maxScore = -1;
      int winnerIdx = 0;
      for (var i = 0; i < game.scores.length; i++) {
        if (game.scores[i] > maxScore) {
          maxScore = game.scores[i];
          winnerIdx = i;
        }
      }
      return '${_playerName(winnerIdx)} won!';
    }
    if (isRemote) {
      return isMyTurn ? 'Your turn' : '${_playerName(game.currentPlayer)}\'s turn';
    }
    return _playerName(game.currentPlayer);
  }

  String get _gameOverText {
    final scores = List.generate(game.playerCount, (i) =>
        '${_playerName(i)}: ${game.scores[i]}').join('\n');
    return scores;
  }

  /// Find the longest word formed by placements on the current board.
  String _longestWordFromPlacements(List<TilePlacement> placements) {
    if (placements.isEmpty) return '?';
    final board = game.board;

    // Determine if horizontal or vertical
    final rows = placements.map((p) => p.row).toSet();
    final isHorizontal = rows.length == 1;

    // Find the main word along the primary axis
    String readWord(int fixedAxis, int start, bool horizontal) {
      final buf = StringBuffer();
      var pos = start;
      while (pos >= 0) {
        final tile = horizontal ? board.get(fixedAxis, pos) : board.get(pos, fixedAxis);
        if (tile == null) break;
        pos--;
      }
      pos++;
      while (pos < Board.size) {
        final tile = horizontal ? board.get(fixedAxis, pos) : board.get(pos, fixedAxis);
        if (tile == null) break;
        buf.write(tile.displayLetter);
        pos++;
      }
      return buf.toString();
    }

    String longest = '';

    if (isHorizontal) {
      final row = placements.first.row;
      final word = readWord(row, placements.first.col, true);
      if (word.length > longest.length) longest = word;
      // Check cross words
      for (final p in placements) {
        final cross = readWord(p.col, p.row, false);
        if (cross.length > longest.length) longest = cross;
      }
    } else {
      final col = placements.first.col;
      final word = readWord(col, placements.first.row, false);
      if (word.length > longest.length) longest = word;
      for (final p in placements) {
        final cross = readWord(p.row, p.col, true);
        if (cross.length > longest.length) longest = cross;
      }
    }

    return longest.isNotEmpty ? longest : '?';
  }

  String? get _lastMoveText {
    final move = _lastMove;
    final playerIdx = _lastMovePlayer;
    if (move == null || playerIdx == null) return null;
    final name = _playerName(playerIdx);
    switch (move.type) {
      case MoveType.play:
        final word = _longestWordFromPlacements(move.placements);
        return '$name played $word for ${move.score} pts';
      case MoveType.pass:
        return '$name passed';
      case MoveType.swap:
        return '$name swapped tiles';
      case MoveType.resign:
        return '$name resigned';
    }
  }

  Set<(int, int)> get _lastMovePositions {
    final move = _lastMove;
    if (move == null || move.type != MoveType.play) return {};
    return {for (final p in move.placements) (p.row, p.col)};
  }

  @override
  Widget build(BuildContext context) {
    // Local mode handover screen
    if (!isRemote && _handover) {
      return Scaffold(
        backgroundColor: const Color(0xFF8B4513),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _handover = false),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _playerName(game.currentPlayer),
                  style: const TextStyle(
                    fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                if (_lastMoveText != null) ...[
                  Text(_lastMoveText!,
                      style: const TextStyle(fontSize: 16, color: Colors.white70)),
                  const SizedBox(height: 12),
                ],
                Text(_scoreText, style: const TextStyle(fontSize: 20, color: Colors.white70)),
                const SizedBox(height: 32),
                const Text('Tap to start your turn',
                    style: TextStyle(color: Colors.white54, fontSize: 18)),
              ],
            ),
          ),
        ),
      );
    }

    final pendingPositions = {for (final p in _pendingPlacements) (p.row, p.col)};
    final lastMovePositions = _lastMovePositions;
    final canInteract = isMyTurn && !game.gameOver;

    return Listener(
      onPointerMove: _dragTile != null ? (e) => _onDragUpdate(e.position) : null,
      onPointerUp: _dragTile != null ? (_) => _onDragEnd() : null,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: const Color(0xFF8B4513),
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_turnLabel, style: const TextStyle(fontSize: 16)),
                  if (_lastMoveText != null)
                    Text(_lastMoveText!,
                        style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ),
              backgroundColor: const Color(0xFF6D3410),
              foregroundColor: Colors.white,
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Tiles left: ${game.bag.length}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      Text('Turn ${game.turnSeqNr + 1}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _BoardWithDrag(
                      key: _boardKey,
                      board: _boardWithPending,
                      pendingPlacements: pendingPositions,
                      lastMovePlacements: lastMovePositions,
                      onCellTap: _onCellTap,
                      onPendingDragStart: _onBoardTileDragStart,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_pendingPlacements.isNotEmpty) ...[
                        Text(
                          '+${_validator.computeScore(game.board, _pendingPlacements)}',
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Text(_scoreText,
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                TileRackWidget(
                  key: _rackKey,
                  tiles: _myRack,
                  onTileDragStart: _onRackTileDragStart,
                  hoverInsertIndex: _dragTile != null ? _rackHoverIndex : null,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: canInteract
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              onPressed: _shuffleRack,
                              icon: const Icon(Icons.shuffle),
                              tooltip: 'Shuffle rack',
                              color: Colors.white70,
                            ),
                            IconButton(
                              onPressed: _pendingPlacements.isNotEmpty ? _recallTiles : null,
                              icon: const Icon(Icons.undo),
                              tooltip: 'Recall tiles',
                              color: Colors.white70,
                            ),
                            ElevatedButton.icon(
                              onPressed: _pendingPlacements.isNotEmpty ? _submitMove : null,
                              icon: const Icon(Icons.check),
                              label: const Text('Play'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            IconButton(
                              onPressed: _swapTiles,
                              icon: const Icon(Icons.swap_horiz),
                              tooltip: 'Swap tiles',
                              color: Colors.white70,
                            ),
                            IconButton(
                              onPressed: _pass,
                              icon: const Icon(Icons.skip_next),
                              tooltip: 'Pass',
                              color: Colors.white70,
                            ),
                          ],
                        )
                      : isRemote && !game.gameOver
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  onPressed: _shuffleRack,
                                  icon: const Icon(Icons.shuffle),
                                  tooltip: 'Shuffle rack',
                                  color: Colors.white70,
                                ),
                                IconButton(
                                  onPressed: _pendingPlacements.isNotEmpty ? _recallTiles : null,
                                  icon: const Icon(Icons.undo),
                                  tooltip: 'Recall tiles',
                                  color: Colors.white70,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${_playerName(game.currentPlayer)}\'s turn',
                                  style: const TextStyle(color: Colors.white54, fontSize: 16),
                                ),
                                if (widget.onHurry != null) ...[
                                  const SizedBox(width: 12),
                                  IconButton(
                                    onPressed: widget.onHurry,
                                    icon: const Icon(Icons.notifications_active),
                                    tooltip: 'Hurry up',
                                    color: Colors.orangeAccent,
                                  ),
                                ],
                              ],
                            )
                          : game.gameOver
                              ? Text(
                                  _gameOverText,
                                  style: const TextStyle(color: Colors.white54, fontSize: 16),
                                  textAlign: TextAlign.center,
                                )
                              : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          // Drag overlay
          if (_dragTile != null)
            Positioned(
              left: _dragPosition.dx - 25,
              top: _dragPosition.dy - 25,
              child: IgnorePointer(
                child: TileWidget(tile: _dragTile!, size: 50, dragging: true),
              ),
            ),
        ],
      ),
    );
  }
}

/// Board wrapper that detects drag starts on pending tiles.
class _BoardWithDrag extends StatelessWidget {
  final Board board;
  final Set<(int, int)> pendingPlacements;
  final Set<(int, int)> lastMovePlacements;
  final void Function(int row, int col)? onCellTap;
  final void Function(int row, int col, Offset globalPosition)? onPendingDragStart;

  const _BoardWithDrag({
    super.key,
    required this.board,
    this.pendingPlacements = const {},
    this.lastMovePlacements = const {},
    this.onCellTap,
    this.onPendingDragStart,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        return Listener(
          onPointerDown: onPendingDragStart == null
              ? null
              : (event) {
                  final (row, col) = BoardWidget.positionToCell(event.localPosition, size);
                  if (pendingPlacements.contains((row, col))) {
                    onPendingDragStart!(row, col, event.position);
                  }
                },
          child: GestureDetector(
            onTapUp: onCellTap == null
                ? null
                : (details) {
                    final (row, col) = BoardWidget.positionToCell(details.localPosition, size);
                    onCellTap!(row, col);
                  },
            child: SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                size: Size(size, size),
                painter: _SimpleBoardPainter(board, pendingPlacements, lastMovePlacements),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SimpleBoardPainter extends CustomPainter {
  final Board board;
  final Set<(int, int)> pendingPlacements;
  final Set<(int, int)> lastMovePlacements;

  _SimpleBoardPainter(this.board, this.pendingPlacements, this.lastMovePlacements);

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = size.width / Board.size;

    for (var r = 0; r < Board.size; r++) {
      for (var c = 0; c < Board.size; c++) {
        final rect = Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize);
        final tile = board.get(r, c);

        if (tile != null) {
          final isPending = pendingPlacements.contains((r, c));
          final isLastMove = lastMovePlacements.contains((r, c));
          final color = isPending
              ? const Color(0xFFFFD54F) // yellow - your pending
              : isLastMove
                  ? const Color(0xFFFFCC80) // orange-ish - opponent's last move
                  : const Color(0xFFE8D5B7); // normal
          canvas.drawRect(rect, Paint()..color = color);
          _drawText(canvas, rect, tile.displayLetter, cellSize * 0.55, Colors.black87);
          _drawText(
            canvas,
            Rect.fromLTWH(rect.left + cellSize * 0.55, rect.top + cellSize * 0.55, cellSize * 0.4, cellSize * 0.4),
            '${tile.points}', cellSize * 0.25, Colors.black54,
          );
        } else {
          final bonus = Board.getBonus(r, c);
          canvas.drawRect(rect, Paint()..color = _bonusColor(bonus));
          if (bonus != CellBonus.none) {
            _drawText(canvas, rect, _bonusLabel(bonus), cellSize * 0.35, Colors.white70);
          }
        }

        canvas.drawRect(rect, Paint()
          ..color = const Color(0xFF5D4037)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5);
      }
    }

    if (board.isEmpty(7, 7)) {
      final center = Rect.fromLTWH(7 * cellSize, 7 * cellSize, cellSize, cellSize);
      _drawText(canvas, center, '\u2605', cellSize * 0.5, Colors.white70);
    }
  }

  void _drawText(Canvas canvas, Rect rect, String text, double fontSize, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(rect.left + (rect.width - tp.width) / 2, rect.top + (rect.height - tp.height) / 2));
  }

  Color _bonusColor(CellBonus bonus) => switch (bonus) {
    CellBonus.doubleLetter => const Color(0xFF64B5F6),
    CellBonus.tripleLetter => const Color(0xFF1565C0),
    CellBonus.doubleWord => const Color(0xFFEF9A9A),
    CellBonus.tripleWord => const Color(0xFFC62828),
    CellBonus.none => const Color(0xFF2E7D32),
  };

  String _bonusLabel(CellBonus bonus) => switch (bonus) {
    CellBonus.doubleLetter => 'DL',
    CellBonus.tripleLetter => 'TL',
    CellBonus.doubleWord => 'DW',
    CellBonus.tripleWord => 'TW',
    CellBonus.none => '',
  };

  @override
  bool shouldRepaint(covariant _SimpleBoardPainter old) => true;
}
