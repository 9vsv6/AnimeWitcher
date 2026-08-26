/// A small, dependency-free scheduler for independent asynchronous work.
///
/// The scheduler keeps results in input order, starts no more than
/// [maxConcurrent] requests at a time, and deliberately does not retry or
/// swallow failures. Those policies belong to the caller because providers
/// have different error semantics.
class BoundedBatchScheduler {
  const BoundedBatchScheduler._();

  static Future<List<R>> mapOrdered<T, R>(
    List<T> items, {
    required int maxConcurrent,
    required Future<R> Function(T item) mapper,
  }) async {
    if (items.isEmpty) return <R>[];

    final workerCount = maxConcurrent.clamp(1, items.length).toInt();
    final results = List<R?>.filled(items.length, null, growable: false);
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        // This synchronous increment happens before the first await, so each
        // worker receives a unique index on Dart's single event loop.
        final index = nextIndex++;
        if (index >= items.length) return;
        results[index] = await mapper(items[index]);
      }
    }

    await Future.wait<void>(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
    return <R>[for (final result in results) result as R];
  }
}
