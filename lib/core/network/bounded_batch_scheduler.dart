/// A small, dependency-free scheduler for independent asynchronous work.
///
/// The scheduler keeps results in input order and starts no more than
/// [BoundedBatchScheduler.mapOrdered]'s `maxConcurrent` requests at a time.
/// It does not retry. Callers that can tolerate a failed item pass [onError];
/// otherwise the first mapper error is propagated to the caller.
class BoundedBatchScheduler {
  const BoundedBatchScheduler._();

  static Future<List<R>> mapOrdered<T, R>(
    List<T> items, {
    required int maxConcurrent,
    required Future<R> Function(T item) mapper,
    R Function(T item, Object error, StackTrace stackTrace)? onError,
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
        try {
          results[index] = await mapper(items[index]);
        } catch (error, stackTrace) {
          if (onError == null) rethrow;
          results[index] = onError(items[index], error, stackTrace);
        }
      }
    }

    await Future.wait<void>(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
    return <R>[for (final result in results) result as R];
  }

  /// Rethrows [error] when every item in a batch failed.
  ///
  /// Callers that isolate per-item failures still need a total-failure path so
  /// a dead network does not look like an empty catalog.
  static void throwIfBatchFailed({
    required int itemCount,
    required int failureCount,
    required Object? error,
    StackTrace? stackTrace,
  }) {
    if (itemCount > 0 && failureCount >= itemCount && error != null) {
      Error.throwWithStackTrace(error, stackTrace ?? StackTrace.current);
    }
  }
}
