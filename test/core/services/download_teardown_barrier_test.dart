import 'dart:async';
import 'dart:io';

import 'package:animewitcher/core/network/dio_client_provider.dart';
import 'package:animewitcher/core/services/download_continued_processing_service.dart';
import 'package:animewitcher/core/services/download_range_transfer.dart';
import 'package:animewitcher/core/services/download_service.dart';
import 'package:animewitcher/core/services/download_service_readiness.dart';
import 'package:animewitcher/core/storage/storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    DownloadService.initializeForTesting = null;
    DownloadService.disposeResourcesForTesting = null;
  });

  test('service initialization enters the lifetime queue before teardown', () {
    final source = File('lib/core/services/download_service.dart')
        .readAsStringSync();
    final initStart = source.indexOf('  Future<void> init() {');
    final initEnd = source.indexOf(
      '  Future<void> _awaitCommandReadiness(',
      initStart,
    );

    expect(initStart, greaterThanOrEqualTo(0));
    expect(initEnd, greaterThan(initStart));
    final init = source.substring(initStart, initEnd);
    expect(
      init,
      contains('_teardownBarrier.run(() async {'),
      reason:
          'an init already in flight must finish before dispose can release a replacement service',
    );
    expect(init, contains('if (_disposed) {'));
    expect(init, contains('await _initialize();'));
  });

  test('dispose before queued initialization prevents platform setup', () async {
    var initialized = false;
    DownloadService.initializeForTesting = () async {
      initialized = true;
    };

    final dio = Dio();
    final scope = ProviderContainer(
      overrides: [
        storageServiceProvider.overrideWithValue(MemoryStorageService()),
        dioClientProvider.overrideWithValue(dio),
      ],
    );
    addTearDown(() {
      DownloadService.initializeForTesting = null;
      DownloadService.disposeResourcesForTesting = null;
      scope.dispose();
      dio.close(force: true);
    });

    final service = scope.read(downloadServiceProvider);
    final initialization = service.init();
    final disposal = service.disposeAsync();

    await expectLater(
      initialization,
      throwsA(isA<DownloadServiceUnavailableException>()),
    );
    await disposal;
    expect(initialized, isFalse);
  });

  test(
    'ProviderScope recreation waits for the old initialization and teardown',
    () async {
      final oldInitializationStarted = Completer<void>();
      final releaseOldInitialization = Completer<void>();
      final teardownStarted = Completer<void>();
      final releaseTeardown = Completer<void>();
      var initializationCount = 0;
      var newInitializationStarted = false;

      DownloadService.initializeForTesting = () async {
        initializationCount += 1;
        if (initializationCount == 1) {
          oldInitializationStarted.complete();
          await releaseOldInitialization.future;
          return;
        }
        newInitializationStarted = true;
      };
      DownloadService.disposeResourcesForTesting = () async {
        teardownStarted.complete();
        await releaseTeardown.future;
      };

      final oldDio = Dio();
      final newDio = Dio();
      final oldScope = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(MemoryStorageService()),
          dioClientProvider.overrideWithValue(oldDio),
        ],
      );
      final newScope = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(MemoryStorageService()),
          dioClientProvider.overrideWithValue(newDio),
        ],
      );
      var oldScopeDisposed = false;
      var newScopeDisposed = false;
      addTearDown(() {
        DownloadService.initializeForTesting = null;
        DownloadService.disposeResourcesForTesting = null;
        if (!oldScopeDisposed) oldScope.dispose();
        if (!newScopeDisposed) newScope.dispose();
        oldDio.close(force: true);
        newDio.close(force: true);
      });

      final oldService = oldScope.read(downloadServiceProvider);
      final oldInitialization = oldService.init();
      await oldInitializationStarted.future;
      oldScope.dispose();
      oldScopeDisposed = true;
      final oldDisposal = oldService.disposeAsync();

      final newService = newScope.read(downloadServiceProvider);
      final newInitialization = newService.init();
      await Future<void>.delayed(Duration.zero);
      expect(newInitializationStarted, isFalse);

      releaseOldInitialization.complete();
      await teardownStarted.future;
      expect(newInitializationStarted, isFalse);

      releaseTeardown.complete();
      await oldInitialization;
      await oldDisposal;
      await newInitialization;
      expect(newInitializationStarted, isTrue);

      DownloadService.initializeForTesting = null;
      DownloadService.disposeResourcesForTesting = null;
      await newService.disposeAsync();
      newScope.dispose();
      newScopeDisposed = true;
    },
  );

  test('service teardown barrier does not release a newer init early', () async {
    final barrier = DownloadServiceTeardownBarrier();
    final release = Completer<void>();
    final teardown = barrier.run(() => release.future);

    var settled = false;
    final waiter = barrier.wait().then((_) => settled = true);
    await Future<void>.delayed(Duration.zero);
    expect(settled, isFalse);

    release.complete();
    await teardown;
    await waiter;
    expect(settled, isTrue);
  });

  test('global handler lease prevents an old instance unregistering the new one', () {
    final oldLease = DownloadGlobalHandlerLease.acquire();
    final newLease = DownloadGlobalHandlerLease.acquire();

    expect(oldLease.releaseIfCurrent(), isFalse);
    expect(newLease.releaseIfCurrent(), isTrue);
  });

}
