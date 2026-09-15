import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native multipart claim offers are created only for background handoff', () {
    final service = File(
      'lib/core/services/download_service.dart',
    ).readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(service, contains('bool _appInForeground = true;'));
    expect(
      service,
      contains('if (Platform.isIOS && !_appInForeground)'),
      reason: 'foreground snapshots must not reserve untouched parts for Swift',
    );
    expect(service, contains('Future<void> onAppBackgrounded() async'));
    expect(
      service,
      contains('_parallel.releaseNativeBackgroundOffers();'),
      reason: 'unclaimed background offers must return to Dart after foreground reconciliation',
    );
    expect(mainSource, contains('onAppBackgrounded()'));
  });
}
