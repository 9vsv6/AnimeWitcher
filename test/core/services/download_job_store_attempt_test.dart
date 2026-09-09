import 'package:animewitcher/core/services/download_job_state.dart';
import 'package:animewitcher/core/services/download_job_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryBackend implements DownloadJobBackend {
  final Map<String, Map<String, dynamic>> values = {};

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
    values[taskId] = Map<String, dynamic>.from(value);
  }
}

DownloadJobRecord _seed({int generation = 3, int durableBytes = 400}) =>
    DownloadJobRecord(
      taskId: 'episode-1',
      trackingUrl: 'https://example.test/watch/1',
      state: DownloadJobState.pausedByUser,
      generation: generation,
      durableBytes: durableBytes,
      expectedBytes: 1000,
      userPaused: true,
      queueWaiting: false,
      updatedAtMillis: 1,
    );

void main() {
  test('beginAttempt atomically increments the durable generation', () async {
    final store = DownloadJobStore(_MemoryBackend());
    expect(await store.put(_seed()), isTrue);

    final token = await store.beginAttempt('episode-1', updatedAtMillis: 2);

    expect(token, isNotNull);
    expect(token!.generation, 4);
    final job = await store.get('episode-1');
    expect(job?.generation, 4);
    expect(job?.state, DownloadJobState.starting);
    expect(job?.durableBytes, 400);
    expect(job?.userPaused, isTrue);
  });

  test('two concurrent beginAttempt calls cannot reuse a generation', () async {
    final store = DownloadJobStore(_MemoryBackend());
    expect(await store.put(_seed(generation: 8)), isTrue);

    final tokens = await Future.wait([
      store.beginAttempt('episode-1', updatedAtMillis: 2),
      store.beginAttempt('episode-1', updatedAtMillis: 3),
    ]);

    expect(tokens.whereType<DownloadAttemptToken>().map((t) => t.generation), {
      9,
      10,
    });
    expect((await store.get('episode-1'))?.generation, 10);
  });

  test('updateForAttempt rejects a callback after a newer resume begins', () async {
    final store = DownloadJobStore(_MemoryBackend());
    expect(await store.put(_seed()), isTrue);
    final oldAttempt = await store.beginAttempt('episode-1');
    final newAttempt = await store.beginAttempt('episode-1');
    expect(oldAttempt, isNotNull);
    expect(newAttempt, isNotNull);

    expect(
      await store.updateForAttempt(
        oldAttempt!,
        state: DownloadJobState.pausedByUser,
        durableBytes: 700,
      ),
      isFalse,
    );
    expect(
      await store.updateForAttempt(
        newAttempt!,
        state: DownloadJobState.running,
        durableBytes: 650,
      ),
      isTrue,
    );

    final job = await store.get('episode-1');
    expect(job?.generation, newAttempt.generation);
    expect(job?.state, DownloadJobState.running);
    expect(job?.durableBytes, 650);
  });

  test('updateForAttempt cannot regress durable bytes', () async {
    final store = DownloadJobStore(_MemoryBackend());
    expect(await store.put(_seed(durableBytes: 500)), isTrue);
    final token = await store.beginAttempt('episode-1');
    expect(token, isNotNull);

    expect(
      await store.updateForAttempt(token!, durableBytes: 499),
      isFalse,
    );
    expect((await store.get('episode-1'))?.durableBytes, 500);
  });

  test('completed jobs cannot begin another attempt', () async {
    final store = DownloadJobStore(_MemoryBackend());
    final completed = _seed(durableBytes: 1000).copyWith(
      state: DownloadJobState.completed,
    );
    expect(await store.put(completed), isTrue);

    expect(await store.beginAttempt('episode-1'), isNull);
    expect((await store.get('episode-1'))?.state, DownloadJobState.completed);
  });
}
