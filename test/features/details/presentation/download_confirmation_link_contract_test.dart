import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('download confirmation exposes and copies the exact direct stream URL', () {
    final source = File(
      'lib/features/details/presentation/download_launcher.dart',
    ).readAsStringSync();

    expect(source, contains("import 'package:flutter/services.dart';"));
    expect(source, contains('ClipboardData(text: stream.url)'));
    expect(source, contains('Icons.copy_rounded'));
    expect(source, contains('TextDirection.ltr'));
    expect(source, contains('TextDirection.rtl'));
  });
}
