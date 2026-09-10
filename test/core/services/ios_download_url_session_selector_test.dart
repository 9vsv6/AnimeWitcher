import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS URLSession hook uses Objective-C NSURLSession selectors', () {
    final source = File('ios/Runner/DownloadNativeWaitingQueue.swift')
        .readAsStringSync();

    // NSURLSession delegate callbacks are exposed to Objective-C with an
    // uppercase `URLSession` selector component. A lowercase selector makes
    // class_getInstanceMethod return nil, so live didWriteData bytes never
    // reach the multipart parent and the UI only moves when a part completes.
    const expectedSelectors = <String>[
      'URLSession:task:didCompleteWithError:',
      'URLSession:downloadTask:didFinishDownloadingToURL:',
      'URLSessionDidFinishEventsForBackgroundURLSession:',
      'URLSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:',
    ];
    for (final selector in expectedSelectors) {
      expect(source, contains('"$selector"'));
    }

    const invalidSelectors = <String>[
      '"urlSession:task:didCompleteWithError:"',
      '"urlSession:downloadTask:didFinishDownloadingToURL:"',
      '"urlSessionDidFinishEventsForBackgroundURLSession:"',
      '"urlSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:"',
    ];
    for (final selector in invalidSelectors) {
      expect(source, isNot(contains(selector)));
    }
  });
}
