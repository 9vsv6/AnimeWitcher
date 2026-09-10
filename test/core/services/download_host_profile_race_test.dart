import 'dart:async';

import 'package:animewitcher/core/services/download_host_profile.dart';
import 'package:flutter_test/flutter_test.dart';

class _GateBackend implements DownloadHostProfileBackend {
  final values = <String, Map<String, dynamic>>{};
  final firstWriteEntered = Completer<void>();
  final releaseFirstWrite = Completer<void>();
  var writes = 0;

  @override
  Future<void> delete(String origin) async => values.remove(origin);

  @override
  Future<Map<String, dynamic>?> read(String origin) async {
    final value = values[origin];
    return value == null ? null : Map<String, dynamic>.from(value);
  }

  @override
  Future<List<Map<String, dynamic>>> readAll() async => values.values
      .map((value) => Map<String, dynamic>.from(value))
      .toList(growable: false);

  @override
  Future<void> write(String origin, Map<String, Object> value) async {
    writes++;
    if (writes == 1) {
      if (!firstWriteEntered.isCompleted) firstWriteEntered.complete();
      await releaseFirstWrite.future;
    }
    values[origin] = Map<String, dynamic>.from(value);
  }
}

void main() {
  test(
    'newer host pressure cannot be overwritten by an older async sample',
    () async {
      final backend = _GateBackend();
      final store = DownloadHostProfileStore(backend);
      final success = store.recordSuccess(
        url: 'https://cdn.test/a.mp4',
        activeConnections: 8,
        bytesPerSecond: 20 * 1024 * 1024,
      );
      await backend.firstWriteEntered.future.timeout(
        const Duration(seconds: 2),
      );

      final pressure = store.recordPressure(
        url: 'https://cdn.test/b.mp4',
        fallbackCeiling: 2,
      );
      backend.releaseFirstWrite.complete();
      await Future.wait(<Future<Object>>[success, pressure]);

      final profile = await store.getForUrl('https://cdn.test/c.mp4');
      expect(profile, isNotNull);
      expect(profile!.safeConnectionCeiling, 2);
      expect(profile.consecutivePressure, 1);
    },
  );
}
