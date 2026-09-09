from pathlib import Path

swift_path = Path('ios/Runner/DownloadNativeWaitingQueue.swift')
text = swift_path.read_text()

replacements = {
    '"urlSession:task:didCompleteWithError:"': '"URLSession:task:didCompleteWithError:"',
    '"urlSession:downloadTask:didFinishDownloadingToURL:"': '"URLSession:downloadTask:didFinishDownloadingToURL:"',
    '"urlSessionDidFinishEventsForBackgroundURLSession:"': '"URLSessionDidFinishEventsForBackgroundURLSession:"',
    '"urlSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:"': '"URLSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:"',
}

for old, new in replacements.items():
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'Expected exactly one {old}, found {count}')
    text = text.replace(old, new)

# Make a failed runtime hook unmistakable in device logs instead of silently
# falling back to whole-part completion updates again.
old_install = '''    let hooked = originalComplete != nil || originalFinishDownload != nil || originalFinishEvents != nil || originalWrite != nil
    if hooked {
      NSLog("[DownloadNativeWaitingQueue] hooked UrlSessionDelegate %@", String(cString: class_getName(delegateClass)))
    }
    return hooked
'''
new_install = '''    let hooked = originalComplete != nil || originalFinishDownload != nil || originalFinishEvents != nil || originalWrite != nil
    if hooked {
      NSLog("[DownloadNativeWaitingQueue] hooked UrlSessionDelegate %@", String(cString: class_getName(delegateClass)))
    } else {
      NSLog(
        "[DownloadNativeWaitingQueue] ERROR: no NSURLSession delegate selectors were hooked on %@",
        String(cString: class_getName(delegateClass))
      )
    }
    return hooked
'''
if text.count(old_install) != 1:
    raise SystemExit('Could not find hook-install result block exactly once')
text = text.replace(old_install, new_install)
swift_path.write_text(text)

test_path = Path('test/core/services/ios_download_url_session_selector_test.dart')
test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS URLSession hook uses Objective-C NSURLSession selectors', () {
    final source = File(
      'ios/Runner/DownloadNativeWaitingQueue.swift',
    ).readAsStringSync();

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
''')

print('Patched NSURLSession Objective-C selectors and added regression test.')
