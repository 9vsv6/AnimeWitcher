import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'continued-processing expiration ends only the OS lease, not the download',
    () async {
      final source = await File(
        'ios/Runner/DownloadContinuedProcessingManager.swift',
      ).readAsString();
      final start = source.indexOf('task.expirationHandler =');
      final end = source.indexOf('\n\n    if let snapshot', start);

      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));

      final expirationBlock = source.substring(start, end);
      expect(expirationBlock, isNot(contains('cancellationHandler?')));
      expect(
        expirationBlock,
        contains('task?.setTaskCompleted(success: false)'),
      );
      expect(expirationBlock, contains('self.activeTask = nil'));
      expect(expirationBlock, contains('self.identifier = nil'));
    },
  );
}
