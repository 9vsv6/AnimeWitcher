import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Discord application whose name and icon head the status. Its id is
/// public (it identifies the app, it grants nothing), so it is set here; a
/// build may override it with `--dart-define=ANIMEWITCHER_DISCORD_CLIENT_ID`.
/// An empty override turns the feature off.
const String kDiscordClientId = String.fromEnvironment(
  'ANIMEWITCHER_DISCORD_CLIENT_ID',
  defaultValue: '1557797923641753601',
);

/// The player setting that turns the status off.
const String kDiscordPresenceSetting = 'player_discord_presence';

/// What is playing, as the Discord status shows it.
class DiscordWatchSnapshot {
  const DiscordWatchSnapshot({
    required this.title,
    required this.isPlaying,
    this.posterUrl,
    this.season,
    this.episode,
    this.positionMs = 0,
    this.durationMs = 0,
  });

  final String title;
  final String? posterUrl;

  /// Null for a film.
  final int? season;
  final int? episode;
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
}

/// The activity sent for [snapshot]: "Watching AnimeWitcher", the title, the
/// season and episode, the poster, and while playing a bar running from the
/// start of the episode to its end. [nowMs] is the wall clock it is set by.
Map<String, Object?> discordActivityFor(
  DiscordWatchSnapshot snapshot, {
  required bool arabic,
  required int nowMs,
}) {
  final title = _fit(snapshot.title.trim(), fallback: 'AnimeWitcher');
  final where = <String>[];
  final season = snapshot.season;
  final episode = snapshot.episode;
  if (episode != null && episode > 0) {
    if (season != null && season > 0) {
      where.add(arabic ? 'الموسم $season' : 'Season $season');
    }
    where.add(arabic ? 'الحلقة $episode' : 'Episode $episode');
  } else {
    where.add(arabic ? 'فيلم' : 'Movie');
  }
  if (!snapshot.isPlaying) {
    where.insert(0, arabic ? 'متوقف مؤقتًا' : 'Paused');
  }

  final poster = snapshot.posterUrl?.trim() ?? '';
  // Discord fetches an https image itself; anything else, or a link longer
  // than it accepts, falls back to the app's own icon.
  final image = poster.startsWith('https://') && poster.length <= 256
      ? poster
      : 'logo';

  final timestamps =
      snapshot.isPlaying &&
          snapshot.durationMs > 0 &&
          snapshot.positionMs <= snapshot.durationMs
      ? <String, Object?>{
          'start': nowMs - snapshot.positionMs,
          'end': nowMs - snapshot.positionMs + snapshot.durationMs,
        }
      : null;

  return <String, Object?>{
    // 3 = "Watching".
    'type': 3,
    'details': title,
    'state': _fit(where.join(' · '), fallback: 'AnimeWitcher'),
    'assets': <String, Object?>{'large_image': image, 'large_text': title},
    if (timestamps != null) 'timestamps': timestamps,
    'instance': false,
  };
}

/// Discord takes 2 to 128 characters in a text field.
String _fit(String text, {required String fallback}) {
  final value = text.length < 2 ? fallback : text;
  return value.length > 128 ? '${value.substring(0, 127)}…' : value;
}

/// Sets the user's Discord status through the desktop client's local IPC
/// socket: a named pipe on Windows, a Unix socket elsewhere. Only the latest
/// activity matters, so updates coalesce, and they are spaced to stay inside
/// Discord's limit of five per twenty seconds. When Discord is not running
/// nothing happens, and the next update tries again.
class DiscordPresence {
  DiscordPresence(
    this.clientId, {
    Future<DiscordIpcTransport?> Function()? connect,
    Duration minInterval = const Duration(seconds: 4),
    Duration retryAfter = const Duration(seconds: 20),
  }) : _connect = connect ?? DiscordIpcTransport.connect,
       _minInterval = minInterval,
       _retryAfter = retryAfter;

  final String clientId;
  final Future<DiscordIpcTransport?> Function() _connect;
  final Duration _minInterval;
  final Duration _retryAfter;

  DiscordIpcTransport? _transport;
  Map<String, Object?>? _wanted;
  bool _hasWanted = false;
  Map<String, Object?>? _sent;
  bool _hasSent = false;
  bool _pumping = false;
  DateTime? _lastSentAt;
  Timer? _retry;
  bool _disposed = false;

  /// Discord's desktop client is only on these; no app id, no status.
  bool get enabled =>
      clientId.isNotEmpty &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Shows [activity], or clears the status when null.
  void update(Map<String, Object?>? activity) {
    if (!enabled || _disposed) return;
    _wanted = activity;
    _hasWanted = true;
    unawaited(_pump());
  }

  void clear() => update(null);

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_hasWanted && !_disposed) {
        final activity = _wanted;
        if (_hasSent && _sameActivity(activity, _sent)) {
          _hasWanted = false;
          break;
        }
        final last = _lastSentAt;
        if (last != null) {
          final wait = _minInterval - DateTime.now().difference(last);
          if (wait > Duration.zero) await Future<void>.delayed(wait);
          // A newer activity may have arrived while waiting; send that.
          if (!identical(activity, _wanted)) continue;
        }
        final transport = _transport ?? await _open();
        if (transport == null) {
          _scheduleRetry();
          break;
        }
        try {
          await transport.request(1, <String, Object?>{
            'cmd': 'SET_ACTIVITY',
            'args': <String, Object?>{'pid': pid, 'activity': activity},
            'nonce': _nonce(),
          });
          _lastSentAt = DateTime.now();
          _sent = activity;
          _hasSent = true;
          if (identical(activity, _wanted)) _hasWanted = false;
        } catch (_) {
          await _drop();
          _scheduleRetry();
          break;
        }
      }
    } finally {
      _pumping = false;
    }
  }

  Future<DiscordIpcTransport?> _open() async {
    final transport = await _connect();
    if (transport == null) return null;
    try {
      final ready = await transport.request(0, <String, Object?>{
        'v': 1,
        'client_id': clientId,
      });
      if (ready['evt'] != 'READY') {
        await transport.close();
        return null;
      }
      _transport = transport;
      // A fresh connection starts with no status; resend whatever is wanted.
      _hasSent = false;
      return transport;
    } catch (_) {
      await transport.close();
      return null;
    }
  }

  Future<void> _drop() async {
    final transport = _transport;
    _transport = null;
    _hasSent = false;
    await transport?.close();
  }

  void _scheduleRetry() {
    if (_disposed || _retry != null) return;
    _retry = Timer(_retryAfter, () {
      _retry = null;
      if (_hasWanted) unawaited(_pump());
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _retry?.cancel();
    await _drop();
  }

  static bool _sameActivity(Object? a, Object? b) =>
      jsonEncode(a) == jsonEncode(b);

  static final Random _random = Random();
  static String _nonce() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
}

/// One connection to the Discord client. Each request is answered by one
/// frame, so requests run one at a time: write, then read the reply.
abstract class DiscordIpcTransport {
  Future<void> write(Uint8List bytes);
  Future<Uint8List> read(int count);
  Future<void> close();

  static const Duration _replyTimeout = Duration(seconds: 5);

  /// Sends one frame and returns the reply's payload. A CLOSE reply (op 2),
  /// such as an unknown client id, is an error.
  Future<Map<String, Object?>> request(
    int op,
    Map<String, Object?> payload,
  ) async {
    await write(encodeDiscordFrame(op, payload));
    final header = ByteData.sublistView(await read(8).timeout(_replyTimeout));
    final replyOp = header.getInt32(0, Endian.little);
    final length = header.getInt32(4, Endian.little);
    if (length < 0 || length > 1 << 20) {
      throw const FormatException('Bad Discord frame');
    }
    final body = await read(length).timeout(_replyTimeout);
    final decoded = jsonDecode(utf8.decode(body));
    final reply = decoded is Map
        ? Map<String, Object?>.from(decoded)
        : <String, Object?>{};
    if (replyOp == 2) {
      throw StateError('Discord closed the connection: ${reply['message']}');
    }
    if (reply['evt'] == 'ERROR') {
      throw StateError('Discord rejected the request: ${reply['data']}');
    }
    return reply;
  }

  /// The first Discord client answering, of the ten sockets it may use; null
  /// when none is running.
  static Future<DiscordIpcTransport?> connect() async {
    for (var index = 0; index < 10; index++) {
      try {
        if (Platform.isWindows) {
          // `\\?\` keeps dart:io from rewriting the pipe path.
          final pipe = await File('\\\\?\\pipe\\discord-ipc-$index')
              .open(mode: FileMode.append);
          return _PipeTransport(pipe);
        }
        for (final dir in _unixSocketDirs()) {
          final path = '$dir/discord-ipc-$index';
          if (await FileSystemEntity.type(path) ==
              FileSystemEntityType.notFound) {
            continue;
          }
          final socket = await Socket.connect(
            InternetAddress(path, type: InternetAddressType.unix),
            0,
            timeout: const Duration(seconds: 2),
          );
          return _SocketTransport(socket);
        }
      } catch (_) {
        // Try the next one.
      }
    }
    return null;
  }

  static List<String> _unixSocketDirs() {
    final env = Platform.environment;
    final bases = <String>{
      for (final key in ['XDG_RUNTIME_DIR', 'TMPDIR', 'TMP', 'TEMP'])
        if ((env[key] ?? '').isNotEmpty)
          env[key]!.replaceAll(RegExp(r'/$'), ''),
      '/tmp',
    };
    return <String>[
      for (final base in bases) ...[
        base,
        // Flatpak and Snap builds of Discord keep their socket in here.
        '$base/app/com.discordapp.Discord',
        '$base/snap.discord',
      ],
    ];
  }
}

/// `[op: int32 LE][length: int32 LE][JSON]`, Discord's IPC frame.
Uint8List encodeDiscordFrame(int op, Map<String, Object?> payload) {
  final body = utf8.encode(jsonEncode(payload));
  final frame = Uint8List(8 + body.length);
  ByteData.sublistView(frame)
    ..setInt32(0, op, Endian.little)
    ..setInt32(4, body.length, Endian.little);
  frame.setRange(8, frame.length, body);
  return frame;
}

class _PipeTransport extends DiscordIpcTransport {
  _PipeTransport(this._pipe);

  final RandomAccessFile _pipe;

  @override
  Future<void> write(Uint8List bytes) => _pipe.writeFrom(bytes);

  @override
  Future<Uint8List> read(int count) async {
    final out = BytesBuilder(copy: false);
    while (out.length < count) {
      final chunk = await _pipe.read(count - out.length);
      if (chunk.isEmpty) throw const SocketException('Discord pipe closed');
      out.add(chunk);
    }
    return out.takeBytes();
  }

  @override
  Future<void> close() async {
    try {
      await _pipe.close();
    } catch (_) {}
  }
}

class _SocketTransport extends DiscordIpcTransport {
  _SocketTransport(this._socket) {
    _subscription = _socket.listen(
      (data) {
        _buffer.add(data);
        _wake();
      },
      onDone: () {
        _closed = true;
        _wake();
      },
      onError: (Object _) {
        _closed = true;
        _wake();
      },
      cancelOnError: true,
    );
  }

  final Socket _socket;
  late final StreamSubscription<Uint8List> _subscription;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  Completer<void>? _waiter;
  bool _closed = false;

  void _wake() {
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  @override
  Future<void> write(Uint8List bytes) async {
    _socket.add(bytes);
    await _socket.flush();
  }

  @override
  Future<Uint8List> read(int count) async {
    while (_buffer.length < count) {
      if (_closed) throw const SocketException('Discord socket closed');
      _waiter = Completer<void>();
      await _waiter!.future;
    }
    final all = _buffer.takeBytes();
    _buffer.add(Uint8List.sublistView(all, count));
    return Uint8List.sublistView(all, 0, count);
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _subscription.cancel();
    _socket.destroy();
  }
}

/// One Discord connection for the whole app, kept across episodes.
final discordPresenceProvider = Provider<DiscordPresence>((ref) {
  final presence = DiscordPresence(kDiscordClientId);
  ref.onDispose(presence.dispose);
  return presence;
});
