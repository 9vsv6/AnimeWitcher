import 'dart:async';

import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/features/details/presentation/source_picker.dart';
import 'package:animewitcher/l10n/generated/app_localizations.dart';
import 'package:animewitcher/shared/widgets/loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sourcePickerHeader', () {
    test('uses the server episode label instead of a generic source prompt', () {
      expect(sourcePickerHeader('الحلقة 10', isArabic: true), 'الحلقة 10');
      expect(sourcePickerHeader('الفيلم', isArabic: true), 'الفيلم');
      expect(sourcePickerHeader('مترجم', isArabic: true), 'مترجم');
    });

    test('keeps the localized generic prompt when no episode is available', () {
      expect(sourcePickerHeader(null, isArabic: true), 'اختر المصدر');
      expect(sourcePickerHeader('  ', isArabic: false), 'Choose source');
    });
  });

  group('episodePickerTitle', () {
    test('uses the primary server label, not the creative title', () {
      expect(
        episodePickerTitle(
          Episode(
            name: 'نهاية الرحلة',
            url: 'https://example.com/ep10',
            episode: 10,
            serverName: 'الحلقة 10',
          ),
        ),
        'الحلقة 10',
      );
      expect(
        episodePickerTitle(
          Episode(
            name: 'مدبلج',
            url: 'https://example.com/movie-dub',
            episode: 0,
            serverName: 'مدبلج',
          ),
        ),
        'مدبلج',
      );
    });

    test('returns null when there is no episode identity', () {
      expect(episodePickerTitle(null), isNull);
      expect(
        episodePickerTitle(
          Episode(name: '', url: 'https://example.com/unknown', episode: 0),
        ),
        isNull,
      );
    });
  });

  testWidgets('shows a loading state in the sheet until servers arrive', (
    tester,
  ) async {
    final pending = Completer<List<StreamResult>>();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                unawaited(
                  showStreamSourcePicker(
                    context,
                    const <StreamResult>[],
                    sourcesFuture: pending.future,
                    forDownload: false,
                    episodeLabel: 'حلقة 9',
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();

    expect(find.text('حلقة 9'), findsOneWidget);
    expect(find.byType(AppLoadingIndicator), findsOneWidget);
    expect(find.text('PD'), findsNothing);

    pending.complete(<StreamResult>[
      const StreamResult(url: 'src-pd', source: 'PD', quality: '1080'),
      const StreamResult(url: 'src-mf', source: 'MF', quality: '720'),
    ]);
    await tester.pumpAndSettle();

    expect(find.byType(AppLoadingIndicator), findsNothing);
    expect(find.text('PD'), findsOneWidget);
    expect(find.text('MF'), findsOneWidget);
  });

  testWidgets('server rows stay tappable above a floating taskbar', (
    tester,
  ) async {
    var taskbarTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          extendBody: true,
          body: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () {
                    unawaited(
                      showStreamSourcePicker(
                        context,
                        const <StreamResult>[
                          StreamResult(
                            url: 'src-pd',
                            source: 'PD',
                            quality: '1080',
                          ),
                        ],
                        forDownload: false,
                        episodeLabel: 'حلقة 9',
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          bottomNavigationBar: SizedBox(
            height: 80,
            child: GestureDetector(
              onTap: () => taskbarTaps++,
              behavior: HitTestBehavior.opaque,
              child: const ColoredBox(
                color: Colors.red,
                child: Center(child: Text('taskbar')),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('PD'), findsOneWidget);
    await tester.tap(find.text('PD'));
    await tester.pumpAndSettle();

    expect(find.text('PD'), findsNothing);
    expect(taskbarTaps, 0);
  });
}
