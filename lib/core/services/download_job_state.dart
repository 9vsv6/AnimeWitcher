import 'package:background_downloader/background_downloader.dart';

/// Logical state of one episode download.
///
/// This deliberately does not mirror [TaskStatus]. Native downloader status,
/// persisted queue metadata and on-disk bytes are evidence about a logical
/// download; none of them should be the state machine by itself.
enum DownloadJobState {
  queued,
  starting,
  running,
  retryWaiting,
  pausing,
  pausedByUser,
  interrupted,
  assembling,
  verifying,
  completed,
  canceled,
  orphaned,
}

/// What startup reconciliation should do after deriving the logical state.
enum DownloadRecoveryAction {
  /// The OS/native downloader still owns the transfer. Attach to it and never
  /// enqueue another copy.
  keepNative,

  /// Rebuild the logical FIFO entry and let the queue scheduler promote it.
  requeue,

  /// An explicit user pause is durable across process death.
  keepPaused,

  /// The row is terminal or there is not enough durable evidence to revive it.
  ignore,
}

class DownloadRecoveryPlan {
  const DownloadRecoveryPlan({required this.state, required this.action});

  final DownloadJobState state;
  final DownloadRecoveryAction action;

  bool get shouldRequeue => action == DownloadRecoveryAction.requeue;
  bool get isNativeOwned => action == DownloadRecoveryAction.keepNative;
}

/// Derive one deterministic startup decision from all durable/native evidence.
///
/// Precedence is intentional:
/// 1. a completed record is terminal;
/// 2. explicit user pause always wins;
/// 3. live native ownership wins over stale persisted status;
/// 4. a durable logical waiter is requeued;
/// 5. interrupted/error states are only revived when AnimeWitcher metadata
///    proves the row belongs to an existing logical download.
DownloadRecoveryPlan planDownloadRecovery({
  required TaskStatus persisted,
  required bool queueWaiting,
  required bool userPaused,
  required bool stillInNativeQueue,
  required bool hasMetadata,
}) {
  if (persisted == TaskStatus.complete) {
    return const DownloadRecoveryPlan(
      state: DownloadJobState.completed,
      action: DownloadRecoveryAction.ignore,
    );
  }

  if (userPaused) {
    return const DownloadRecoveryPlan(
      state: DownloadJobState.pausedByUser,
      action: DownloadRecoveryAction.keepPaused,
    );
  }

  if (stillInNativeQueue) {
    final state = switch (persisted) {
      TaskStatus.enqueued => DownloadJobState.starting,
      TaskStatus.waitingToRetry => DownloadJobState.retryWaiting,
      _ => DownloadJobState.running,
    };
    return DownloadRecoveryPlan(
      state: state,
      action: DownloadRecoveryAction.keepNative,
    );
  }

  if (queueWaiting) {
    return const DownloadRecoveryPlan(
      state: DownloadJobState.queued,
      action: DownloadRecoveryAction.requeue,
    );
  }

  switch (persisted) {
    case TaskStatus.enqueued:
    case TaskStatus.running:
    case TaskStatus.waitingToRetry:
      return const DownloadRecoveryPlan(
        state: DownloadJobState.interrupted,
        action: DownloadRecoveryAction.requeue,
      );

    case TaskStatus.paused:
    case TaskStatus.failed:
    case TaskStatus.notFound:
      return DownloadRecoveryPlan(
        state: hasMetadata
            ? DownloadJobState.interrupted
            : DownloadJobState.orphaned,
        action: hasMetadata
            ? DownloadRecoveryAction.requeue
            : DownloadRecoveryAction.ignore,
      );

    case TaskStatus.canceled:
      // Explicit delete removes AnimeWitcher metadata before recovery. A
      // canceled row with metadata is therefore treated as a system/native
      // interruption; without metadata it must never be resurrected.
      return DownloadRecoveryPlan(
        state: hasMetadata
            ? DownloadJobState.interrupted
            : DownloadJobState.canceled,
        action: hasMetadata
            ? DownloadRecoveryAction.requeue
            : DownloadRecoveryAction.ignore,
      );

    case TaskStatus.complete:
      // Handled before the precedence checks above.
      return const DownloadRecoveryPlan(
        state: DownloadJobState.completed,
        action: DownloadRecoveryAction.ignore,
      );
  }
}

/// Identifies one concrete execution attempt of a logical episode.
///
/// Future native/plugin callbacks can carry this token (directly or through a
/// side table). A callback is accepted only while its token is current, which
/// prevents late events from an old pause/retry/restart attempt from mutating a
/// newer download state.
class DownloadAttemptToken {
  const DownloadAttemptToken({required this.taskId, required this.generation});

  final String taskId;
  final int generation;

  @override
  bool operator ==(Object other) =>
      other is DownloadAttemptToken &&
      other.taskId == taskId &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(taskId, generation);
}

/// In-memory attempt fence with monotonic generations per logical task.
///
/// The API accepts an optional persisted seed so this can later be backed by
/// DownloadJobStore without changing callback filtering semantics.
class DownloadAttemptFence {
  DownloadAttemptFence([Map<String, int>? persistedGenerations]) {
    if (persistedGenerations == null) return;
    for (final entry in persistedGenerations.entries) {
      final taskId = entry.key.trim();
      final generation = entry.value;
      if (taskId.isEmpty || generation < 0) continue;
      _generations[taskId] = generation;
    }
  }

  final Map<String, int> _generations = <String, int>{};

  DownloadAttemptToken begin(String taskId) {
    final id = taskId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(taskId, 'taskId', 'must not be empty');
    }
    final next = (_generations[id] ?? 0) + 1;
    _generations[id] = next;
    return DownloadAttemptToken(taskId: id, generation: next);
  }

  /// Invalidates every callback issued before this call without starting work.
  DownloadAttemptToken invalidate(String taskId) => begin(taskId);

  bool accepts(DownloadAttemptToken token) {
    if (token.generation <= 0) return false;
    return _generations[token.taskId] == token.generation;
  }

  int generationFor(String taskId) => _generations[taskId.trim()] ?? 0;

  Map<String, int> snapshot() => Map<String, int>.unmodifiable(_generations);
}
