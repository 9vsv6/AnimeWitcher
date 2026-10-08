import 'dart:convert';
import 'dart:typed_data';

import 'package:animewitcher/core/discord/discord_presence.dart';
import 'package:animewitcher/features/player/presentation/discord_presence_driver.dart';
import 'package:flutter_test/flutter_test.dart';

const _poster = 'https://s4.anilist.co/file/anilistcdn/media/anime/cover/x.jpg';

void main() {
  group('the status', () {
    test('a playing episode: title, season and episode, poster, time bar', () {
      final activity = discordActivityFor(
        const DiscordWatchSnapshot(
          title: 'Sousou no Frieren',
          posterUrl: _poster,
          season: 1,
          episode: 5,
          isPlaying: true,
          positionMs: 60000,
          durationMs: 1440000,
        ),
        arabic: true,
        nowMs: 1000000,
      );
      expect(activity['type'], 3);
      expect(activity['details'], 'Sousou no Frieren');
      expect(activity['state'], 'الموسم 1 · الحلقة 5');
      expect(activity['assets'], {
        'large_image': _poster,
        'large_text': 'Sousou no Frieren',
      });
      expect(activity['timestamps'], {'start': 940000, 'end': 2380000});
    });

    test('paused: said so, and no running time bar', () {
      final activity = discordActivityFor(
        const DiscordWatchSnapshot(
          title: 'Frieren',
          season: 2,
          episode: 3,
          isPlaying: false,
          positionMs: 60000,
          durationMs: 1440000,
        ),
        arabic: false,
        nowMs: 1000000,
      );
      expect(activity['state'], 'Paused · Season 2 · Episode 3');
      expect(activity.containsKey('timestamps'), isFalse);
    });

    test(
      'a film, and a poster Discord cannot fetch falls back to the icon',
      () {
        final activity = discordActivityFor(
          const DiscordWatchSnapshot(
            title: 'Koe no Katachi',
            posterUrl: 'http://insecure.example/poster.jpg',
            isPlaying: true,
          ),
          arabic: true,
          nowMs: 0,
        );
        expect(activity['state'], 'فيلم');
        expect((activity['assets'] as Map)['large_image'], 'logo');
      },
    );
  });

  group('the driver', () {
    late _RecordingPresence presence;
    late DiscordWatchSnapshot? current;
    late int now;
    late DiscordPresenceDriver driver;

    setUp(() {
      presence = _RecordingPresence();
      now = 1000000;
      current = const DiscordWatchSnapshot(
        title: 'Frieren',
        season: 1,
        episode: 1,
        isPlaying: true,
        positionMs: 0,
        durationMs: 1440000,
      );
      driver = DiscordPresenceDriver(
        snapshot: () => current,
        presence: presence,
        arabic: true,
        nowMillis: () => now,
      );
    });

    DiscordWatchSnapshot at(
      int positionMs, {
      bool playing = true,
      int ep = 1,
    }) => DiscordWatchSnapshot(
      title: 'Frieren',
      season: 1,
      episode: ep,
      isPlaying: playing,
      positionMs: positionMs,
      durationMs: 1440000,
    );

    test('normal playback sends once; Discord runs the bar itself', () {
      driver.tick();
      for (var second = 3; second <= 30; second += 3) {
        now += 3000;
        current = at(second * 1000);
        driver.tick();
      }
      expect(presence.updates, hasLength(1));
    });

    test('pause, seek and the next episode each send an update', () {
      driver.tick();
      now += 3000;
      current = at(3000, playing: false);
      driver.tick();
      now += 3000;
      current = at(3000);
      driver.tick();
      now += 3000;
      current = at(600000); // seeked forward ten minutes
      driver.tick();
      now += 3000;
      current = at(0, ep: 2);
      driver.tick();
      expect(presence.updates, hasLength(5));
      expect(presence.updates.last?['state'], 'الموسم 1 · الحلقة 2');
    });

    test('leaving the player clears the status', () {
      driver.tick();
      driver.stop();
      expect(presence.updates.last, isNull);
    });
  });

  group('the connection', () {
    test('handshakes, then sets the activity, once per change', () async {
      final transport = _FakeDiscord();
      final presence = DiscordPresence(
        '1234567890',
        connect: () async => transport,
        minInterval: Duration.zero,
      );
      addTearDown(presence.dispose);
      final activity = {'type': 3, 'details': 'Frieren'};
      presence.update(activity);
      presence.update(Map<String, Object?>.from(activity));
      await transport.settled();

      expect(transport.requests.map((r) => r.op), [0, 1]);
      expect(transport.requests.first.payload, {
        'v': 1,
        'client_id': '1234567890',
      });
      final set = transport.requests.last.payload;
      expect(set['cmd'], 'SET_ACTIVITY');
      expect((set['args'] as Map)['activity'], activity);
    });

    test('an unknown app id is refused quietly, with nothing sent', () async {
      final transport = _FakeDiscord(refuseHandshake: true);
      final presence = DiscordPresence(
        '1',
        connect: () async => transport,
        minInterval: Duration.zero,
        retryAfter: const Duration(hours: 1),
      );
      addTearDown(presence.dispose);
      presence.update({'type': 3, 'details': 'Frieren'});
      await transport.settled();
      expect(transport.requests.map((r) => r.op), [0]);
      expect(transport.closed, isTrue);
    });

    test('frames are op and length, little-endian, then JSON', () {
      final frame = encodeDiscordFrame(1, {'a': 1});
      final header = ByteData.sublistView(frame, 0, 8);
      expect(header.getInt32(0, Endian.little), 1);
      expect(header.getInt32(4, Endian.little), 7);
      expect(utf8.decode(frame.sublist(8)), '{"a":1}');
    });
  });
}

class _RecordingPresence extends DiscordPresence {
  _RecordingPresence() : super('test');

  final List<Map<String, Object?>?> updates = <Map<String, Object?>?>[];

  @override
  void update(Map<String, Object?>? activity) => updates.add(activity);
}

class _Request {
  _Request(this.op, this.payload);
  final int op;
  final Map<String, Object?> payload;
}

/// Answers like the Discord client: READY to a handshake (or a CLOSE for a
/// bad app id), and an echo of each command.
class _FakeDiscord extends DiscordIpcTransport {
  _FakeDiscord({this.refuseHandshake = false});

  final bool refuseHandshake;
  final List<_Request> requests = <_Request>[];
  final BytesBuilder _replies = BytesBuilder();
  bool closed = false;

  Future<void> settled() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  @override
  Future<void> write(Uint8List bytes) async {
    final header = ByteData.sublistView(bytes, 0, 8);
    final op = header.getInt32(0, Endian.little);
    final payload = Map<String, Object?>.from(
      jsonDecode(utf8.decode(bytes.sublist(8))) as Map,
    );
    requests.add(_Request(op, payload));
    if (op == 0) {
      _replies.add(
        refuseHandshake
            ? encodeDiscordFrame(2, {
                'code': 4000,
                'message': 'Invalid Client ID',
              })
            : encodeDiscordFrame(1, {'cmd': 'DISPATCH', 'evt': 'READY'}),
      );
    } else {
      _replies.add(
        encodeDiscordFrame(1, {
          'cmd': payload['cmd'],
          'nonce': payload['nonce'],
        }),
      );
    }
  }

  @override
  Future<Uint8List> read(int count) async {
    final all = _replies.takeBytes();
    _replies.add(all.sublist(count));
    return Uint8List.fromList(all.sublist(0, count));
  }

  @override
  Future<void> close() async => closed = true;
}
