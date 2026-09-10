import 'dart:async';

import 'package:animewitcher/core/services/download_job_state.dart';
import 'package:animewitcher/core/services/download_job_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _FaultBackend implements DownloadJobBackend {
  final values = <String, Map<String, dynamic>>{};
  var failNextWrite = false;
  Completer<void>? blockNextWrite;

  @override
  Future<void> delete(String taskId) async => values.remove(taskId);

  @override
  Future<Map<String, dynamic>?> read(String taskId) async {
    final value = values[taskId];
    return value == null ? null : Map<String, dynamic>.from(value);
  }

  @override
  Future<List<Map<String, dynamic>>> readAll() async => values.values
      .map((value) => Map<String, dynamic>.from(value))
      .toList(growable: false);

  @override
  Future<void> write(String taskId, Map<String, Object?> value) async {
    final blocker = blockNextWrite;
    blockNextWrite = null;
    if (blocker != null) await blocker.future;
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('injected storage failure');
    }
    values[taskId] = Map<String, dynamic>.from(value);
  }
}

DownloadResourceFingerprint get fingerprint =>
    const DownloadResourceFingerprint(
      strongEtag: '"ep-v1"',
      expectedBytes: 100,
    );

Future<bool> checkpoint(
  DownloadJobStore store, {
  DownloadJobState state = DownloadJobState.running,
  int bytes = 0,
}) => store.checkpoint(
  taskId: 'ep',
  trackingUrl: 'tracking://ep',
  state: state,
  durableBytes: bytes,
  expectedBytes: 100,
  userPaused: state == DownloadJobState.pausedByUser,
  queueWaiting: state == DownloadJobState.queued,
  fingerprint: fingerprint,
);

void main() {
  test(
    'write failure does not poison the serialized checkpoint chain',
    () async {
      final backend = _FaultBackend()..failNextWrite = true;
      final store = DownloadJobStore(backend);
      await expectLater(checkpoint(store, bytes: 10), throwsStateError);
      expect(await checkpoint(store, bytes: 12), isTrue);
      expect((await store.get('ep'))?.durableBytes, 12);
    },
  );

  test('concurrent lifecycle writes are applied in invocation order', () async {
    final backend = _FaultBackend();
    final store = DownloadJobStore(backend);
    expect(await checkpoint(store, bytes: 10), isTrue);

    final gate = Completer<void>();
    backend.blockNextWrite = gate;
    final first = checkpoint(store, state: DownloadJobState.running, bytes: 20);
    await Future<void>.delayed(Duration.zero);
    final second = checkpoint(
      store,
      state: DownloadJobState.pausedByUser,
      bytes: 25,
    );
    gate.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    final job = await store.get('ep');
    expect(job?.durableBytes, 25);
    expect(job?.state, DownloadJobState.pausedByUser);
    expect(job?.userPaused, isTrue);
  });

  test('pause racing completion cannot regress a completed job', () async {
    final backend = _FaultBackend();
    final store = DownloadJobStore(backend);
    expect(await checkpoint(store, bytes: 90), isTrue);
    expect(
      await checkpoint(store, state: DownloadJobState.completed, bytes: 100),
      isTrue,
    );
    expect(
      await checkpoint(store, state: DownloadJobState.pausedByUser, bytes: 100),
      isFalse,
    );
    expect((await store.get('ep'))?.state, DownloadJobState.completed);
  });

  test('late callback from pre-relaunch generation is rejected', () async {
    final backend = _FaultBackend();
    final firstProcess = DownloadJobStore(backend);
    expect(await checkpoint(firstProcess, bytes: 40), isTrue);
    final old = await firstProcess.beginAttempt('ep');
    expect(old, isNotNull);
    expect(await firstProcess.updateForAttempt(old!, durableBytes: 55), isTrue);

    final relaunched = DownloadJobStore(backend);
    final current = await relaunched.beginAttempt('ep');
    expect(current, isNotNull);
    expect(await relaunched.updateForAttempt(old, durableBytes: 80), isFalse);
    expect((await relaunched.get('ep'))?.durableBytes, 55);
  });

  test(
    'delete boundary invalidates old attempts and permits a true zero reset',
    () async {
      final backend = _FaultBackend();
      final store = DownloadJobStore(backend);
      expect(await checkpoint(store, bytes: 75), isTrue);
      final old = await store.beginAttempt('ep');
      expect(old, isNotNull);
      await store.remove('ep');
      expect(await store.accepts(old!), isFalse);
      expect(await checkpoint(store, bytes: 0), isTrue);
      expect((await store.get('ep'))?.durableBytes, 0);
    },
  );
}
