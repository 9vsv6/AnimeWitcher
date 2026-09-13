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
}
