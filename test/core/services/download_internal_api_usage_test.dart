import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DownloadService never accesses downloaderForTesting directly', () {
    final service = File('lib/core/services/download_service.dart').readAsStringSync();
    expect(service, isNot(contains('downloaderForTesting')));
  });

  test('internal plugin access stays isolated in one compatibility seam', () {
    final compat = File('lib/core/services/download_plugin_compat.dart')
        .readAsStringSync();
    expect(RegExp('downloaderForTesting').allMatches(compat).length, 2);
  });
}
