import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS continued-processing cannot report a partial file as complete', () async {
    final source = await File(
      'ios/Runner/DownloadContinuedProcessingManager.swift',
    ).readAsString();

    expect(source, contains('let snapshotLooksComplete: Bool'));
    expect(source, contains('snapshot.progress >= 0.999_999'));
    expect(
      source,
      contains(
        'snapshot.completedCount + 1 >= max(snapshot.batchTotal, 1)',
      ),
    );
    expect(source, contains('let verifiedSuccess = success && snapshotLooksComplete'));
    expect(source, contains('task.setTaskCompleted(success: verifiedSuccess)'));
  });
}
