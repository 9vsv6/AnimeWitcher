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
}
