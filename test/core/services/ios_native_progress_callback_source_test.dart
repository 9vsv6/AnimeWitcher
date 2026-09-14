import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS progress observation uses supported background_downloader callback', () {
    final swift = File(
      'ios/Runner/DownloadNativeWaitingQueue.swift',
    ).readAsStringSync();

    expect(swift, contains('BDPlugin.onNativeTaskProgressChange'));
    expect(swift, isNot(contains('writeSelector')));
    expect(swift, isNot(contains('hookWrite')));
    expect(swift, isNot(contains('didWriteData')));

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
    expect(RegExp(r'hookComplete\(on:').allMatches(swift).length, 2);
    expect(RegExp(r'hookFinishDownload\(on:').allMatches(swift).length, 2);
    expect(RegExp(r'hookFinishEvents\(on:').allMatches(swift).length, 2);
    expect(swift, contains('completeSelector'));
    expect(swift, contains('finishDownloadSelector'));
    expect(swift, contains('finishEventsSelector'));

    // Hook discovery is a compatibility seam, not a launch precondition. If a
    // future plugin version removes these internal selectors, install returns
    // false instead of fabricating a second progress observer or crashing.
    expect(swift, contains('guard let delegateClass = findUrlSessionDelegateClass() else'));
    expect(swift, contains('return false'));
  });

  test('AppDelegate installs the compatibility seam at launch and background wake', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    // Startup and a background URLSession wake are the only installation sites;
    // installUrlSessionHook() is internally idempotent.
    expect(
      RegExp(r'DownloadNativeWaitingQueue\.installUrlSessionHook\(\)')
          .allMatches(appDelegate)
          .length,
      2,
    );
    expect(appDelegate, contains('didFinishLaunchingWithOptions'));
    expect(appDelegate, contains('handleEventsForBackgroundURLSession'));
  });
}
