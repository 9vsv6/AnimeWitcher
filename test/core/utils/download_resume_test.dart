import 'package:animewitcher/core/utils/download_resume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses a successful native resume when resume data is available', () async {
    var resumeCalls = 0;
    var restartCalls = 0;

    final result = await resumeOrRestartDownload(
      canResume: () async => true,
      resume: () async {
        resumeCalls++;
        return true;
      },
      restart: () async {
        restartCalls++;
        return true;
      },
    );

    expect(result, isTrue);
    expect(resumeCalls, 1);
    expect(restartCalls, 0);
  });

  test('restarts when native resume data is unavailable', () async {
    var resumeCalls = 0;
    var restartCalls = 0;

    final result = await resumeOrRestartDownload(
      canResume: () async => false,
      resume: () async {
        resumeCalls++;
        return true;
      },
      restart: () async {
        restartCalls++;
        return true;
      },
    );

    expect(result, isTrue);
    expect(resumeCalls, 0);
    expect(restartCalls, 1);
  });

  test('restarts when a native resume attempt is rejected', () async {
    var restartCalls = 0;

    final result = await resumeOrRestartDownload(
      canResume: () async => true,
      resume: () async => false,
      restart: () async {
        restartCalls++;
        return false;
      },
    );

    expect(result, isFalse);
    expect(restartCalls, 1);
  });

  test('restarts when a native resume attempt throws', () async {
    var restartCalls = 0;

    final result = await resumeOrRestartDownload(
      canResume: () async => true,
      resume: () async => throw StateError('stale resume data'),
      restart: () async {
        restartCalls++;
        return true;
      },
    );

    expect(result, isTrue);
    expect(restartCalls, 1);
  });

  test('restarts when checking resumability throws for a stale task', () async {
    var restartCalls = 0;

    final result = await resumeOrRestartDownload(
      canResume: () async => throw StateError('missing resume metadata'),
      resume: () async => true,
      restart: () async {
        restartCalls++;
        return true;
      },
    );

    expect(result, isTrue);
    expect(restartCalls, 1);
  });
}
