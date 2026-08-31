import 'dart:io';

import 'package:animewitcher/core/services/download_concurrency.dart';
import 'package:animewitcher/core/storage/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('aw_download_concurrency_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<StorageService> bindFreshBox(String name) async {
    final box = await Hive.openBox<dynamic>(name);
    final storage = StorageService()..debugBindSettingsBox(box);
    return storage;
  }

  test('Hive settings default to 1 and clamp 1–5', () async {
    final storage = await bindFreshBox('download_concurrency_default');

    expect(storage.getDownloadConcurrency(), 1);

    await storage.setDownloadConcurrency(0);
    expect(storage.getDownloadConcurrency(), 1);

    await storage.setDownloadConcurrency(5);
    expect(storage.getDownloadConcurrency(), 5);

    await storage.setDownloadConcurrency(8);
    expect(storage.getDownloadConcurrency(), 5);
  });

  test('Hive round-trips a live 1–5 change', () async {
    final storage = await bindFreshBox('download_concurrency_roundtrip');
    await storage.setDownloadConcurrency(4);
    expect(storage.getDownloadConcurrency(), 4);
    expect(storage.getDownloadConcurrency(), clampDownloadConcurrency(4));
  });

  test('Hive round-trips the active download FIFO order', () async {
    final storage = await bindFreshBox('download_queue_order');
    expect(storage.getDownloadQueueOrder(), isEmpty);
    await storage.setDownloadQueueOrder(const ['ep1', 'ep3', 'ep2']);
    expect(storage.getDownloadQueueOrder(), ['ep1', 'ep3', 'ep2']);
  });
}
