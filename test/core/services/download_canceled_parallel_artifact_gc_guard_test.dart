import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _methodBody(String source, String startSignature, String endSignature) {
  final start = source.indexOf(startSignature);
  final end = source.indexOf(endSignature, start + startSignature.length);
  expect(start, greaterThanOrEqualTo(0), reason: 'missing $startSignature');
  expect(end, greaterThan(start), reason: 'missing boundary $endSignature');
  return source.substring(start, end);
}

void main() {
  test('canceled multipart GC removes owned artifacts only after ownership release', () {
    final source = File('lib/core/services/download_service.dart')
        .readAsStringSync();
    final body = _methodBody(
      source,
      'Future<void> _garbageCollectCanceledTombstones() async {',
      'Future<int> _occupiedSlotCount(',
    );

    final ownershipCheck = body.indexOf(
      'ownership != DownloadRuntimeOwnership.notOwned',
    );
    final parallelTypeCheck = body.indexOf('restored is ParallelDownloadTask');
    final parallelCancel = body.indexOf('_parallel.cancel(restored)');
    final finalFileDelete = body.indexOf('deleteDownloadedFile(file)');

    expect(ownershipCheck, greaterThanOrEqualTo(0));
    expect(parallelTypeCheck, greaterThan(ownershipCheck));
    expect(parallelCancel, greaterThan(parallelTypeCheck));
    expect(finalFileDelete, greaterThan(parallelCancel));
  });
}
