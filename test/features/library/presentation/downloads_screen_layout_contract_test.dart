import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('handset downloads lets the tabs own the top safe area', () {
    final screen = File(
      'lib/features/library/presentation/downloads_screen.dart',
    ).readAsStringSync();

    expect(screen, isNot(contains('child: AppBar(')));
    expect(screen, contains('body: SafeArea('));
    expect(screen, contains('child: const DownloadsTab()'));
  });

  test('download tabs remain visible when there are no records', () {
    final tab = File(
      'lib/features/library/presentation/widgets/downloads_tab.dart',
    ).readAsStringSync();

    expect(tab, isNot(contains('if (downloads.isEmpty)')));
    expect(tab, contains('FilterStyleTabBar('));
    expect(tab, contains('FilterStyleTab(label: l10n.downloads)'));
    expect(tab, contains('FilterStyleTab(label: l10n.downloadsTabCompleted)'));
  });
}
