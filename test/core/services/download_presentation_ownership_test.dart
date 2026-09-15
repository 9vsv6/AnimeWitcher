import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('downloads presentation never owns lifecycle persistence or cleanup', () {
    final source = File(
      'lib/features/library/presentation/downloads_provider.dart',
    ).readAsStringSync();

    expect(
      source,
      isNot(contains('FileDownloader().database.updateRecord(')),
      reason: 'presentation must not rewrite executor lifecycle state',
    );
    expect(
      source,
      isNot(contains('FileDownloader().database.deleteRecordWithId(')),
      reason: 'presentation must not delete executor database records',
    );
    expect(
      source,
      isNot(contains('storage.removeDownloadMetadata(')),
      reason: 'presentation must not delete lifecycle metadata',
    );
    expect(
      source,
      isNot(contains('deleteDownloadedEpisodeArtwork(')),
      reason: 'presentation should submit commands and project snapshots only',
    );
  });

  test('downloads presentation reads service-owned logical snapshots only', () {
    final presentation = File(
      'lib/features/library/presentation/downloads_provider.dart',
    ).readAsStringSync();
    final service = File(
      'lib/core/services/download_service.dart',
    ).readAsStringSync();

    expect(
      presentation,
      isNot(contains('FileDownloader().database.allRecords(')),
      reason: 'raw executor inventory belongs behind DownloadService',
    );
    expect(
      presentation,
      isNot(contains('storageServiceProvider')),
      reason: 'presentation must not merge lifecycle metadata itself',
    );
    expect(
      presentation,
      contains('logicalDownloadSnapshots('),
      reason: 'list refresh must consume a service-owned logical snapshot',
    );
    expect(
      presentation,
      contains('logicalDownloadSnapshotForTask('),
      reason: 'new task projection must also use the service snapshot seam',
    );
    expect(service, contains('Future<List<DownloadLogicalSnapshot>>'));
  });
}
