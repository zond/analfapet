import 'dart:convert';
import 'dart:typed_data';
import '../models/board.dart';
import '../models/move.dart';
import '../models/remote_game.dart';
import '../models/tile.dart';

/// Binary message codec for encoding/decoding game messages as base64.
///
/// Type 0x01: Friend request
///   0x01 | uuid (1 byte len + bytes) | name (1 byte len + bytes)
///
/// Type 0x02: Game state
///   0x02
///   | gameId (1 byte len + bytes)
///   | seed (4 bytes, big-endian uint32)
///   | playerCount (1 byte)
///   | for each player:
///       | uuid (1 byte len + bytes)
///       | name (1 byte len + bytes)
///       | status (1 byte: 0=pending, 1=accepted, 2=denied)
///   | moveCount (2 bytes, big-endian uint16)
///   | for each move:
///       | type (1 byte: 0=play, 1=pass, 2=swap, 3=resign)
///       | if play:
///           | placementCount (1 byte)
///           | for each placement:
///               | row (1 byte)
///               | col (1 byte)
///               | letter (1 byte len + UTF-8 bytes)
///               | points (1 byte)
///               | isBlank (1 byte: 0 or 1)
///               | if isBlank: blankLetter (1 byte len + UTF-8 bytes)
///           | score (2 bytes, big-endian uint16)
///       | if swap:
///           | count (1 byte)
///           | for each: letter (1 byte len + UTF-8 bytes)
class MessageCodec {
  static const int typeFriend = 0x01;
  static const int typeGame = 0x02;

  /// Encode a friend request to a base64 string.
  static String encodeFriendRequest(String uuid, String name) {
    final builder = BytesBuilder();
    builder.addByte(typeFriend);
    _writeString(builder, uuid);
    _writeString(builder, name);
    return base64Encode(builder.toBytes());
  }

  /// Encode a full game state to a base64 string.
  static String encodeGameState(RemoteGame game) {
    final builder = BytesBuilder();
    builder.addByte(typeGame);
    _writeString(builder, game.gameId);
    _writeUint32(builder, game.seed);
    builder.addByte(game.players.length);
    for (final player in game.players) {
      _writeString(builder, player.uuid);
      _writeString(builder, player.name);
      builder.addByte(player.status);
    }
    _writeUint16(builder, game.moves.length);
    for (final move in game.moves) {
      builder.addByte(move.type.index);
      if (move.type == MoveType.play) {
        builder.addByte(move.placements.length);
        for (final p in move.placements) {
          builder.addByte(p.row);
          builder.addByte(p.col);
          _writeString(builder, p.placedTile.tile.letter);
          builder.addByte(p.placedTile.tile.points);
          final isBlank = p.placedTile.blankLetter != null;
          builder.addByte(isBlank ? 1 : 0);
          if (isBlank) {
            _writeString(builder, p.placedTile.blankLetter!);
          }
        }
        _writeUint16(builder, move.score);
      } else if (move.type == MoveType.swap) {
        final letters = move.swappedTileLetters ?? [];
        builder.addByte(letters.length);
        for (final letter in letters) {
          _writeString(builder, letter);
        }
      }
      // pass and resign have no additional data
    }
    return base64Encode(builder.toBytes());
  }

  /// Decode a base64 string into a typed message map.
  ///
  /// Returns either:
  ///   {'type': 'friend', 'uuid': String, 'name': String}
  /// or:
  ///   {'type': 'game', 'gameId': String, 'seed': int, 'players': [...], 'moves': [...]}
  static Map<String, dynamic> decode(String base64Str) {
    final bytes = base64Decode(base64Str);
    final reader = _ByteReader(bytes);
    final type = reader.readByte();

    if (type == typeFriend) {
      final uuid = reader.readString();
      final name = reader.readString();
      return {'type': 'friend', 'uuid': uuid, 'name': name};
    }

    if (type == typeGame) {
      final gameId = reader.readString();
      final seed = reader.readUint32();
      final playerCount = reader.readByte();
      final players = <Map<String, dynamic>>[];
      for (var i = 0; i < playerCount; i++) {
        final uuid = reader.readString();
        final name = reader.readString();
        final status = reader.readByte();
        players.add({'uuid': uuid, 'name': name, 'status': status});
      }
      final moveCount = reader.readUint16();
      final moves = <Move>[];
      for (var i = 0; i < moveCount; i++) {
        final moveType = MoveType.values[reader.readByte()];
        if (moveType == MoveType.play) {
          final placementCount = reader.readByte();
          final placements = <TilePlacement>[];
          for (var j = 0; j < placementCount; j++) {
            final row = reader.readByte();
            final col = reader.readByte();
            final letter = reader.readString();
            final points = reader.readByte();
            final isBlank = reader.readByte() == 1;
            String? blankLetter;
            if (isBlank) {
              blankLetter = reader.readString();
            }
            placements.add(TilePlacement(
              row,
              col,
              PlacedTile(Tile(letter, points), blankLetter: blankLetter),
            ));
          }
          final score = reader.readUint16();
          moves.add(Move(
            type: MoveType.play,
            turnSeqNr: i,
            boardHash: '', // boardHash is recomputed during validation
            placements: placements,
            score: score,
          ));
        } else if (moveType == MoveType.swap) {
          final count = reader.readByte();
          final letters = <String>[];
          for (var j = 0; j < count; j++) {
            letters.add(reader.readString());
          }
          moves.add(Move(
            type: MoveType.swap,
            turnSeqNr: i,
            boardHash: '',
            swappedTileLetters: letters,
          ));
        } else {
          // pass or resign
          moves.add(Move(
            type: moveType,
            turnSeqNr: i,
            boardHash: '',
          ));
        }
      }
      return {
        'type': 'game',
        'gameId': gameId,
        'seed': seed,
        'players': players,
        'moves': moves,
      };
    }

    throw FormatException('Unknown message type: $type');
  }

  static void _writeString(BytesBuilder builder, String s) {
    final bytes = utf8.encode(s);
    if (bytes.length > 255) {
      throw FormatException('String too long: ${bytes.length} bytes');
    }
    builder.addByte(bytes.length);
    builder.add(bytes);
  }

  static void _writeUint16(BytesBuilder builder, int value) {
    builder.addByte((value >> 8) & 0xFF);
    builder.addByte(value & 0xFF);
  }

  static void _writeUint32(BytesBuilder builder, int value) {
    builder.addByte((value >> 24) & 0xFF);
    builder.addByte((value >> 16) & 0xFF);
    builder.addByte((value >> 8) & 0xFF);
    builder.addByte(value & 0xFF);
  }

  /// Return a short human-readable type string for the service worker.
  static String notificationType(RemoteGame game) {
    // Check if any player newly denied
    if (game.players.any((p) => p.denied)) return 'deny';
    // Check if game has moves
    if (game.moves.isNotEmpty) return 'move';
    // Check if all accepted
    if (game.allAccepted) return 'accept';
    // Otherwise it's an invite
    return 'invite';
  }
}

/// Helper for sequential reading from a byte buffer.
class _ByteReader {
  final Uint8List _bytes;
  int _offset = 0;

  _ByteReader(List<int> bytes) : _bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  int readByte() => _bytes[_offset++];

  int readUint16() {
    final high = _bytes[_offset++];
    final low = _bytes[_offset++];
    return (high << 8) | low;
  }

  int readUint32() {
    final b0 = _bytes[_offset++];
    final b1 = _bytes[_offset++];
    final b2 = _bytes[_offset++];
    final b3 = _bytes[_offset++];
    return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
  }

  String readString() {
    final len = readByte();
    final strBytes = _bytes.sublist(_offset, _offset + len);
    _offset += len;
    return utf8.decode(strBytes);
  }
}
