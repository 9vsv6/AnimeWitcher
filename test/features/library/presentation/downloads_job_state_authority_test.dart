import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DM-05 downloads projection authority', () {
    test('downloads provider projects durable JobState snapshots', () {
      final source = File(
        'lib/features/library/presentation/downloads_provider.dart',
      ).readAsStringSync();

      expect(source, contains('logicalJobStateForTask'));
      expect(source, contains('downloadJobDisplayStatus'));
      expect(source, contains('Pre-JobStore migration fallback'));

      final refresh = source.indexOf('Future<List<DownloadItem>> _refreshList()');
      final handler = source.indexOf('Future<void> _handleUpdate(', refresh);
      expect(refresh, greaterThanOrEqualTo(0));
      expect(handler, greaterThan(refresh));
      final refreshBody = source.substring(refresh, handler);

      // _refreshList no longer inspects raw FileDownloader records. The service
      // constructs logical snapshots first, and the provider projects the
      // durable logical state from that snapshot into the UI row.
      expect(refreshBody, contains('logicalDownloadSnapshots()'));
      expect(refreshBody, contains('logicalState: snapshot.logicalState'));
      expect(refreshBody, isNot(contains('TaskStatus.failed')));
      expect(refreshBody, isNot(contains('TaskStatus.notFound')));
    });

    test('live plugin callbacks are projected through JobState when available', () {
      final source = File(
        'lib/features/library/presentation/downloads_provider.dart',
      ).readAsStringSync();
      final handler = source.indexOf('Future<void> _handleUpdate(');
      final remove = source.indexOf('Future<void> removeDownload(', handler);
      expect(handler, greaterThanOrEqualTo(0));
      expect(remove, greaterThan(handler));
      final body = source.substring(handler, remove);

      expect(body, contains('logicalJobStateForTask'));
      expect(body, contains('downloadJobDisplayStatus'));
    });
  });
}
