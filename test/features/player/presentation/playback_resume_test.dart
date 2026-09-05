import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:animewitcher/features/player/presentation/playback_resume.dart';

void main() {
  group('PlaybackResume.openWhenReady', () {
    test('exiting a fresh download during cloud lookup prevents autoplay', () async {
      final cloud = Completer<int>();
      var active = true;
      var opens = 0;
      final startup = PlaybackResume.openWhenReady(
        isActive: () => active,
        resolvePosition: () => PlaybackResume.resolveStartupPosition(
          localPositionMs: 0,
          cloudPositionMs: () => cloud.future,
        ),
        open: (_) async { opens++; },
      );

      // Back stops the engine while the no-bookmark path is still waiting.
      active = false;
      cloud.complete(0);
      expect(await startup, isFalse);
      expect(opens, 0);
    });

    test('a late bookmark cannot open over a replacement episode', () async {
      final cloud = Completer<int>();
      var currentSession = 1;
      final requestedSession = currentSession;
      var opens = 0;
      final startup = PlaybackResume.openWhenReady(
        isActive: () => currentSession == requestedSession,
        resolvePosition: () => cloud.future,
        open: (_) async { opens++; },
      );
      currentSession = 2;
      cloud.complete(90000);
      expect(await startup, isFalse);
      expect(opens, 0);
    });

    test('cloud failure after leaving cannot fall back to autoplay', () async {
      final cloud = Completer<int>();
      var active = true;
      var opens = 0;
      final startup = PlaybackResume.openWhenReady(
        isActive: () => active,
        resolvePosition: () => PlaybackResume.resolveStartupPosition(
          localPositionMs: 0,
          cloudPositionMs: () => cloud.future,
        ),
        open: (_) async { opens++; },
      );
      active = false;
      cloud.completeError(StateError('offline'));
      expect(await startup, isFalse);
      expect(opens, 0);
    });

    test('active playback keeps the existing resume position', () async {
      int? openedAt;
      final opened = await PlaybackResume.openWhenReady(
        isActive: () => true,
        resolvePosition: () => PlaybackResume.resolveStartupPosition(
          localPositionMs: 120000,
          cloudPositionMs: () async => throw StateError('must use local bookmark'),
        ),
        open: (position) async { openedAt = position; },
      );
      expect(opened, isTrue);
      expect(openedAt, 120000);
    });

    test('exit during engine open skips subsequent resume work', () async {
      final opening = Completer<void>();
      final started = Completer<void>();
      var active = true;
      final startup = PlaybackResume.openWhenReady(
        isActive: () => active,
        resolvePosition: () async => 90000,
        open: (_) {
          started.complete();
          return opening.future;
        },
      );
      await started.future;
      active = false;
      opening.complete();
      expect(await startup, isFalse);
    });
  });

  group('PlaybackResume.shouldHoldUntilSeeked', () {
    test('holds for a mid-episode bookmark', () {
      expect(PlaybackResume.shouldHoldUntilSeeked(15 * 60 * 1000), isTrue);
    });

    test('does not hold a fresh start', () {
      expect(PlaybackResume.shouldHoldUntilSeeked(0), isFalse);
      expect(PlaybackResume.shouldHoldUntilSeeked(500), isFalse);
      expect(
        PlaybackResume.shouldHoldUntilSeeked(PlaybackResume.minPositionMs - 1),
        isFalse,
      );
      expect(
        PlaybackResume.shouldHoldUntilSeeked(PlaybackResume.minPositionMs),
        isTrue,
      );
    });
  });

  group('PlaybackResume.isNear', () {
    test('accepts HLS keyframe landings within the settle window', () {
      expect(
        PlaybackResume.isNear(currentMs: 180_000, targetMs: 184_000),
        isTrue,
      );
      expect(PlaybackResume.isNear(currentMs: 0, targetMs: 180_000), isFalse);
    });
  });

  group('PlaybackResume.canRevealVideo', () {
    test('hides the first frames until the playhead reaches the bookmark', () {
      expect(
        PlaybackResume.canRevealVideo(
          pendingResumeMs: 180000,
          applyingResume: false,
          currentMs: 400,
        ),
        isFalse,
      );
      expect(
        PlaybackResume.canRevealVideo(
          pendingResumeMs: 180000,
          applyingResume: true,
          currentMs: 180000,
        ),
        isFalse,
      );
      expect(
        PlaybackResume.canRevealVideo(
          pendingResumeMs: 180000,
          applyingResume: false,
          currentMs: 180200,
        ),
        isTrue,
      );
    });

    test('reveals a fresh start as soon as playback advances', () {
      expect(
        PlaybackResume.canRevealVideo(
          pendingResumeMs: null,
          applyingResume: false,
          currentMs: 80,
        ),
        isTrue,
      );
    });
  });

  group('PlaybackResume.shouldAwaitCloudResume', () {
    test('skips the cloud when a local bookmark is already usable', () {
      expect(PlaybackResume.shouldAwaitCloudResume(15000), isFalse);
      expect(PlaybackResume.shouldAwaitCloudResume(180000), isFalse);
    });

    test('asks the cloud for downloaded and streaming starts with no bookmark',
        () {
      expect(PlaybackResume.shouldAwaitCloudResume(0), isTrue);
      expect(PlaybackResume.shouldAwaitCloudResume(500), isTrue);
    });
  });

  group('PlaybackResume.resolveStartupPosition', () {
    test('opens immediately when a local bookmark already exists', () async {
      final never = Completer<int>();
      final stopwatch = Stopwatch()..start();
      final position = await PlaybackResume.resolveStartupPosition(
        localPositionMs: 12000,
        cloudPositionMs: () => never.future,
        cloudTimeout: const Duration(seconds: 5),
      );
      stopwatch.stop();

      expect(position, 12000);
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
    });

    test('uses a fast cloud bookmark for downloaded and streaming starts',
        () async {
      final downloaded = await PlaybackResume.resolveStartupPosition(
        localPositionMs: 0,
        cloudPositionMs: () async => 90000,
      );
      final streamed = await PlaybackResume.resolveStartupPosition(
        localPositionMs: 0,
        cloudPositionMs: () async => 45000,
      );
      expect(downloaded, 90000);
      expect(streamed, 45000);
    });

    test('caps downloaded and streaming cloud resume at two seconds', () {
      expect(
        PlaybackResume.cloudResumeTimeout,
        const Duration(seconds: 2),
      );
    });

    test('fails open to local progress when cloud resume times out', () async {
      final never = Completer<int>();
      final stopwatch = Stopwatch()..start();
      final position = await PlaybackResume.resolveStartupPosition(
        localPositionMs: 0,
        cloudPositionMs: () => never.future,
        cloudTimeout: const Duration(milliseconds: 40),
      );
      stopwatch.stop();

      expect(position, 0);
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(40));
    });
  });
}
