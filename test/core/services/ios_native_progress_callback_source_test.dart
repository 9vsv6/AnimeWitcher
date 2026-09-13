import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS progress observation uses supported background_downloader callback', () {
    final swift = File('ios/Runner/DownloadNativeWaitingQueue.swift').readAsStringSync();

    expect(swift, contains('BDPlugin.onNativeTaskProgressChange'));
    expect(swift, isNot(contains('writeSelector')));
    expect(swift, isNot(contains('hookWrite')));

    // DM-26 intentionally keeps the narrower completion-ordering compatibility
    // seam until behavioral tests prove those hooks can be removed safely.
    expect(swift, contains('completeSelector'));
    expect(swift, contains('finishDownloadSelector'));
    expect(swift, contains('finishEventsSelector'));
  });
}
