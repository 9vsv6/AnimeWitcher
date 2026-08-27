import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:animewitcher/features/player/presentation/playback_resume.dart';

void main() {
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
