import 'package:animewitcher/core/network/bounded_batch_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps input order while capping concurrent work', () async {
    var active = 0;
    var peak = 0;
    final delays = <int>[35, 5, 25, 10, 1];

    final results = await BoundedBatchScheduler.mapOrdered<int, String>(
      <int>[0, 1, 2, 3, 4],
      maxConcurrent: 2,
      mapper: (value) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(Duration(milliseconds: delays[value]));
        active--;
        return 'item-$value';
      },
    );

    expect(peak, 2);
    expect(results, <String>['item-0', 'item-1', 'item-2', 'item-3', 'item-4']);
  });

  test('uses one worker for a non-positive requested limit', () async {
    var peak = 0;
    var active = 0;

    final results = await BoundedBatchScheduler.mapOrdered<int, int>(
      <int>[1, 2, 3],
      maxConcurrent: 0,
      mapper: (value) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        active--;
        return value * 2;
      },
    );

    expect(peak, 1);
    expect(results, <int>[2, 4, 6]);
  });

  test('does not invoke the mapper for an empty batch', () async {
    var invocations = 0;

    final results = await BoundedBatchScheduler.mapOrdered<int, int>(
      const <int>[],
      maxConcurrent: 3,
      mapper: (value) async {
        invocations++;
        return value;
      },
    );

    expect(results, isEmpty);
    expect(invocations, 0);
  });

  test('propagates mapper errors when onError is omitted', () async {
    final started = <int>[];

    await expectLater(
      BoundedBatchScheduler.mapOrdered<int, int>(
        <int>[1, 2, 3],
        maxConcurrent: 2,
        mapper: (value) async {
          started.add(value);
          if (value == 2) throw StateError('section-2');
          await Future<void>.delayed(const Duration(milliseconds: 1));
          return value;
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'section-2',
        ),
      ),
    );
    expect(started, contains(2));
  });

  test('onError keeps remaining items and preserves input order', () async {
    final results = await BoundedBatchScheduler.mapOrdered<int, String>(
      <int>[0, 1, 2, 3],
      maxConcurrent: 2,
      mapper: (value) async {
        if (value == 1) throw StateError('section-1');
        await Future<void>.delayed(Duration(milliseconds: value == 0 ? 20 : 1));
        return 'ok-$value';
      },
      onError: (value, error, stackTrace) => 'fail-$value',
    );

    expect(results, <String>['ok-0', 'fail-1', 'ok-2', 'ok-3']);
  });

  test('onError can return null without dropping later items', () async {
    final results = await BoundedBatchScheduler.mapOrdered<int, String?>(
      <int>[0, 1, 2],
      maxConcurrent: 2,
      mapper: (value) async {
        if (value == 1) throw StateError('section-1');
        return 'ok-$value';
      },
      onError: (value, error, stackTrace) => null,
    );

    expect(results, <String?>['ok-0', null, 'ok-2']);
  });

  test('throwIfBatchFailed is a no-op when any item succeeded', () {
    BoundedBatchScheduler.throwIfBatchFailed(
      itemCount: 3,
      failureCount: 1,
      error: StateError('section-1'),
    );
  });

  test('throwIfBatchFailed rethrows when every item failed', () {
    expect(
      () => BoundedBatchScheduler.throwIfBatchFailed(
        itemCount: 2,
        failureCount: 2,
        error: StateError('offline'),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'offline',
        ),
      ),
    );
  });

  test('throwIfBatchFailed is a no-op for an empty batch', () {
    BoundedBatchScheduler.throwIfBatchFailed(
      itemCount: 0,
      failureCount: 0,
      error: StateError('unused'),
    );
  });
}
