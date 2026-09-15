import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS native observation uses supported 9.6.1 callbacks', () {
    final swift = File(
      'ios/Runner/DownloadNativeWaitingQueue.swift',
    ).readAsStringSync();

    expect(swift, contains('BDPlugin.onNativeTaskProgressChange'));
    expect(swift, contains('BDPlugin.onNativeTaskStatusChange'));
    expect(swift, contains('handleSupportedPluginStatus('));
    expect(swift, isNot(contains('writeSelector')));
    expect(swift, isNot(contains('hookWrite')));
    expect(
      swift,
      isNot(
        contains(
          'URLSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:',
        ),
      ),
    );

    // Supported plugin progress must preserve the multipart parent bridge rather
    // than treating child taskIds as independent logical downloads.
    expect(
      swift,
      contains(
        'postSupportedMultipartProgress(task: task, progress: normalized)',
      ),
    );
    expect(swift, contains('private static func postMultipartChunkSample('));
    expect(swift, contains('AnimeWitcherBackgroundDownloaderChunkUpdate'));
    expect(swift, contains('expectedBytesFromRangeHeader'));

    // DM-26 intentionally keeps only the completion/promotion ordering seam.
    // Progress must have exactly one observation path: the supported callback.
    expect(RegExp(r'hookComplete\(on:').allMatches(swift).length, 1);
    expect(RegExp(r'func hookComplete\(on ').allMatches(swift).length, 1);
    expect(RegExp(r'hookFinishDownload\(on:').allMatches(swift).length, 1);
    expect(RegExp(r'func hookFinishDownload\(on ').allMatches(swift).length, 1);
    expect(RegExp(r'hookFinishEvents\(on:').allMatches(swift).length, 1);
    expect(RegExp(r'func hookFinishEvents\(on ').allMatches(swift).length, 1);
    expect(swift, contains('completeSelector'));
    expect(swift, contains('finishDownloadSelector'));
    expect(swift, contains('finishEventsSelector'));
    expect(swift, contains('animeWitcherBackgroundDownloaderVersion'));
    expect(swift, isNot(contains('Bundle(for: BDPlugin.self)')));
    expect(swift, isNot(contains('supportedTerminalStatusesByTaskId')));
    expect(swift, contains('terminalObservation.capture('));
    expect(swift, contains('installation.install('));
    expect(swift, contains('guard nativePromotionAvailable else { return }'));

    // Wiring guard only; test/native/dm26_compatibility_test.swift exercises
    // every partial-selector combination and delayed status isolation.
    expect(swift, contains('guard let delegateClass = findUrlSessionDelegateClass() else'));
    expect(swift, contains('return false'));
  });

  test('AppDelegate installs the compatibility seam at launch and background wake', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    // Startup, background wake and each fresh checkpoint retry installation.
    expect(
      RegExp(r'DownloadNativeWaitingQueue\.installUrlSessionHook\(\)')
          .allMatches(appDelegate)
          .length,
      3,
    );
    expect(appDelegate, contains('didFinishLaunchingWithOptions'));
    expect(appDelegate, contains('handleEventsForBackgroundURLSession'));
  });
}
