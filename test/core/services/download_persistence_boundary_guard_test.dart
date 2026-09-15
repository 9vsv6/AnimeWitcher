import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('start range and completion fail closed on authoritative persistence', () {
    final source = File('lib/core/services/download_service.dart')
        .readAsStringSync();

    final startBegin = source.indexOf(
      'Future<DownloadCommandOutcome> startDownloadOutcome({',
    );
    final startEnd = source.indexOf(
      'Future<List<TaskRecord>> _completeRecordsForEpisode(',
      startBegin,
    );
    final start = source.substring(startBegin, startEnd);
    expect(startBegin, greaterThanOrEqualTo(0));
    expect(start, contains('_jobStore.beginReplicaTransactionFromSeed('));
    expect(
      start,
      contains(r"throw StateError('Failed to persist fresh download intent')"),
    );
    expect(
      start.indexOf('_jobStore.beginReplicaTransactionFromSeed('),
      lessThan(start.indexOf('_waitingPayloads[transferTask.taskId]')),
    );

    final rangeBegin = source.indexOf(
      'Future<DownloadAttemptToken?> _beginLogicalRangeAttempt(',
    );
    final rangeEnd = source.indexOf(
      'Future<({DownloadTask task, bool refreshed, bool restartRequired})>',
      rangeBegin,
    );
    final range = source.substring(rangeBegin, rangeEnd);
    expect(range, contains('if (!await _jobStore.put('));
    expect(range, contains('return null;'));

    final completeBegin = source.indexOf(
      'Future<void> _persistCompletedFilePath(Task task)',
    );
    final completeEnd = source.indexOf(
      'Future<String> getDownloadPath(',
      completeBegin,
    );
    final complete = source.substring(completeBegin, completeEnd);
    expect(
      complete,
      contains('final completedPersisted = await _checkpointLogicalJob('),
    );
    expect(complete, contains("if (!completedPersisted)"));
    expect(
      complete.indexOf(
        'final completedPersisted = await _checkpointLogicalJob(',
      ),
      lessThan(complete.indexOf('.patchDownloadMetadata(')),
    );
  });
}
