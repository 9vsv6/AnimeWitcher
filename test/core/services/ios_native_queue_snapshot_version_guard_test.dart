import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DM-15 queue checkpoints carry a monotonic version and native ack', () {
    final dartBridge = File(
      'lib/core/services/download_continued_processing_service.dart',
    ).readAsStringSync();
    final swiftQueue = File('ios/Runner/DownloadNativeWaitingQueue.swift')
        .readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(dartBridge, contains("'snapshotVersion': snapshotVersion"));
    expect(dartBridge, contains('Future<int?> persistNativeQueue'));
    expect(dartBridge, contains("ack['acceptedVersion']"));

    expect(swiftQueue, contains('var snapshotVersion: Int'));
    expect(
      swiftQueue,
      contains('let snapshotVersion = intValue(arguments["snapshotVersion"])'),
    );
    expect(swiftQueue, contains('snapshotVersion < current.snapshotVersion'));
    expect(swiftQueue, contains('return current.snapshotVersion'));

    expect(
      appDelegate,
      contains(
        'let acceptedVersion = DownloadNativeWaitingQueue.persist(from: arguments)',
      ),
    );
    expect(appDelegate, contains('"acceptedVersion": acceptedVersion'));
  });
}
