import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('continued-processing handler is registered during app launch', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final manager = File(
      'ios/Runner/DownloadContinuedProcessingManager.swift',
    ).readAsStringSync();

    final launch = appDelegate.indexOf('didFinishLaunchingWithOptions');
    final launchReturn = appDelegate.indexOf(
      'return super.application(application, didFinishLaunchingWithOptions: launchOptions)',
      launch,
    );
    final registration = appDelegate.indexOf(
      'DownloadContinuedProcessingManager.shared.registerLaunchHandler()',
      launch,
    );

    expect(launch, greaterThanOrEqualTo(0));
    expect(launchReturn, greaterThan(launch));
    expect(
      registration,
      allOf(greaterThan(launch), lessThan(launchReturn)),
      reason: 'BGTaskScheduler launch handlers must be registered before applicationDidFinishLaunching returns',
    );
    expect(manager, contains('func registerLaunchHandler() throws'));
  });
}
