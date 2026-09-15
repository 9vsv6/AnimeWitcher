import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('continued-processing update reports whether native still owns a session', () {
    final manager = File(
      'ios/Runner/DownloadContinuedProcessingManager.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final appDelegate = File(
      'ios/Runner/AppDelegate.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(manager, contains('func update(\n'));
    expect(
      manager,
      contains(') -> Bool {'),
      reason: 'Dart must be able to detect a system task that expired or vanished',
    );
    expect(
      manager,
      contains('guard var snapshot = snapshot else { return false }'),
    );
    expect(appDelegate, contains('let active = manager.update('));
    expect(appDelegate, contains('result(active)'));
  });
}
