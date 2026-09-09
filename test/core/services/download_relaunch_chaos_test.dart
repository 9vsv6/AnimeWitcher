import 'package:animewitcher/core/services/download_job_state.dart';
import 'package:animewitcher/core/services/download_job_store.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

class _SharedMemoryBackend implements DownloadJobBackend {
  final Map<String, Map<String, dynamic>> values = <String, Map<String, dynamic>>{};

  @override
  Future<void> delete(String taskId) async => values.remove(taskId);

  @override
  Future<Map<String, dynamic>?> read(String taskId) async {
    final raw = values[taskId];
    return raw == null ? null : Map<String, dynamic>.from(raw);
  }

  @override
  Future<List<Map<String, dynamic>>> readAll() async => values.values
      .map((raw) => Map<String, dynamic>.from(raw))
      .toList(growable: false);

  @override
  Future<void> write(String taskId, Map<String, Object?> value) async {
    values[taskId] = Map<String, dynamic>.from(value);
  }
}

DownloadJobRecord _seed({
  DownloadJobState state = DownloadJobState.running,
  int generation = 0,
  int durableBytes = 40,
  bool userPaused = false,
  bool queueWaiting = false,
}) => DownloadJobRecord(
  taskId: 'ep-7',
  trackingUrl: 'https://anime.test/episode/7',
  state: state,
  generation: generation,
  durableBytes: durableBytes,
  expectedBytes: 100,
  userPaused: userPaused,
  queueWaiting: queueWaiting,
  updatedAtMillis: 1,
  fingerprint: const DownloadResourceFingerprint(
    strongEtag: '"episode-seven"',
    expectedBytes: 100,
  ),
);

void main() {
  test('kill/relaunch preserves bytes and rejects callback from old process', () async {
    final backend = _SharedMemoryBackend();
    final beforeKill = DownloadJobStore(backend);
    expect(await beforeKill.put(_seed()), isTrue);

    final firstAttempt = await beforeKill.beginAttempt('ep-7');
    expect(firstAttempt, isNotNull);
    expect(
      await beforeKill.updateForAttempt(
        firstAttempt!,
        state: DownloadJobState.running,
        durableBytes: 61,
      ),
      isTrue,
    );

    // New store instance models a completely new Dart process using the same
    // durable Hive data after the OS killed the app.
    final afterRelaunch = DownloadJobStore(backend);
    final secondAttempt = await afterRelaunch.beginAttempt('ep-7');
    expect(secondAttempt, isNotNull);
    expect(secondAttempt!.generation, greaterThan(firstAttempt.generation));

    // A delayed native/Dio callback from the dead process must be ignored even
    // if it reports more bytes than the old checkpoint.
    expect(
      await afterRelaunch.updateForAttempt(
        firstAttempt,
        state: DownloadJobState.pausedByUser,
        durableBytes: 80,
        userPaused: true,
      ),
      isFalse,
    );
    final current = await afterRelaunch.get('ep-7');
    expect(current?.generation, secondAttempt.generation);
    expect(current?.durableBytes, 61);
    expect(current?.userPaused, isFalse);
  });

  test('user pause survives relaunch and recovery never promotes it', () async {
    final backend = _SharedMemoryBackend();
    final store = DownloadJobStore(backend);
    expect(
      await store.put(
        _seed(
          state: DownloadJobState.pausedByUser,
          generation: 4,
          durableBytes: 73,
          userPaused: true,
        ),
      ),
      isTrue,
    );

    final relaunched = DownloadJobStore(backend);
    final job = await relaunched.get('ep-7');
    expect(job?.durableBytes, 73);
    final plan = planDownloadRecovery(
      persisted: TaskStatus.failed,
      queueWaiting: false,
      userPaused: job!.userPaused,
      stillInNativeQueue: false,
      hasMetadata: true,
    );
    expect(plan.state, DownloadJobState.pausedByUser);
    expect(plan.action, DownloadRecoveryAction.keepPaused);
    expect(plan.shouldRequeue, isFalse);
  });

  test('system cancellation requeues but explicit delete stays deleted', () async {
    final interrupted = planDownloadRecovery(
      persisted: TaskStatus.canceled,
      queueWaiting: false,
      userPaused: false,
      stillInNativeQueue: false,
      hasMetadata: true,
    );
    expect(interrupted.action, DownloadRecoveryAction.requeue);

    final userDeleted = planDownloadRecovery(
      persisted: TaskStatus.canceled,
      queueWaiting: false,
      userPaused: false,
      stillInNativeQueue: false,
      hasMetadata: false,
    );
    expect(userDeleted.action, DownloadRecoveryAction.ignore);
    expect(userDeleted.state, DownloadJobState.canceled);
  });

  test('delete is the only chaos boundary that can legitimately return to zero', () async {
    final backend = _SharedMemoryBackend();
    final store = DownloadJobStore(backend);
    expect(await store.put(_seed(generation: 9, durableBytes: 92)), isTrue);

    expect(
      await store.put(_seed(generation: 10, durableBytes: 0)),
      isFalse,
    );
    expect((await store.get('ep-7'))?.durableBytes, 92);

    await store.remove('ep-7');
    expect(await store.put(_seed(generation: 0, durableBytes: 0)), isTrue);
    expect((await store.get('ep-7'))?.durableBytes, 0);
  });
}
