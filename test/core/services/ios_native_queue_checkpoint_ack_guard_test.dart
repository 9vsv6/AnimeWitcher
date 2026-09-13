import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DM-15 correctness queue checkpoint must not swallow missing native ack', () {
    final source = File('lib/core/services/download_service.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _persistNativeWaitingSnapshot');
    expect(start, isNonNegative);
    final end = source.indexOf('\n  String? _notificationConfigJson', start);
    expect(end, greaterThan(start));
    final body = source.substring(start, end);

    expect(
      body,
      contains('final acceptedVersion = await _continuedProcessing.persistNativeQueue('),
    );
    expect(body, contains('if (acceptedVersion == null)'));
    expect(body, contains("diagnosticLog.record('nativeQueue.checkpointUnacknowledged'"));
    expect(body, contains("throw StateError('Native waiting queue checkpoint was not acknowledged')"));
  });
}
