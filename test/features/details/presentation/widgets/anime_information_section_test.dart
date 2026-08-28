import 'dart:io';
import 'dart:ui' as ui;

import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/features/details/presentation/widgets/anime_information_section.dart';
import 'package:animewitcher/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

MultimediaItem _item({
  String? source,
  int? duration,
  Map<String, String>? syncData,
}) {
  return MultimediaItem(
    title: 'تجريبي',
    url: 'https://example.test/anime',
    posterUrl: '',
    source: source,
    duration: duration,
    syncData: syncData,
  );
}

Widget _app(Widget child, {String? fontFamily}) {
  return MaterialApp(
    locale: const Locale('ar'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFEEC60A),
        surface: Color(0xFF111111),
        onSurface: Color(0xFFE5E7EB),
        onSurfaceVariant: Color(0xFFB0B0B0),
      ),
    ),
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

void main() {
  test('hides the app name when no real source exists', () {
    expect(
      displayableAnimeSource(syncSource: null, itemSource: 'AnimeWitcher'),
      isNull,
    );
    expect(
      displayableAnimeSource(
        syncSource: 'AnimeWitcher Native',
        itemSource: 'AnimeWitcher',
      ),
      isNull,
    );
    expect(
      displayableAnimeSource(syncSource: 'Manga', itemSource: 'AnimeWitcher'),
      'Manga',
    );
  });

  test('treats question marks as missing metadata', () {
    expect(cleanAnimeInfoValue('?'), isNull);
    expect(cleanAnimeInfoValue('؟'), isNull);
    expect(cleanAnimeInfoValue('2024-01-08'), '2024-01-08');
  });

  testWidgets('omits source when only AnimeWitcher is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        AnimeInformationSection(
          item: _item(
            source: 'AnimeWitcher',
            duration: 16,
            syncData: const {'awDuration': '16'},
          ),
        ),
      ),
    );

    expect(find.text('المصدر'), findsNothing);
    expect(find.text('AnimeWitcher'), findsNothing);
    expect(find.text('مدة الحلقة'), findsOneWidget);
    expect(find.text('بداية العرض'), findsNothing);
    expect(find.text('نهاية العرض'), findsNothing);
  });

  testWidgets('shows a real source and hides empty air dates', (tester) async {
    await tester.pumpWidget(
      _app(
        AnimeInformationSection(
          item: _item(
            source: 'AnimeWitcher',
            duration: 24,
            syncData: const {'awSource': 'Manga', 'awDuration': '24'},
          ),
        ),
      ),
    );

    expect(find.text('المصدر'), findsOneWidget);
    expect(find.text('Manga'), findsOneWidget);
    expect(find.text('بداية العرض'), findsNothing);
    expect(find.text('نهاية العرض'), findsNothing);
  });

  testWidgets('shows both air dates when only the start date exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        AnimeInformationSection(
          item: _item(
            duration: 16,
            syncData: const {'awDuration': '16', 'awStartDate': '2024-01-08'},
          ),
        ),
      ),
    );

    expect(find.text('بداية العرض'), findsOneWidget);
    expect(find.text('2024-01-08'), findsOneWidget);
    expect(find.text('نهاية العرض'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('shows both air dates when only the end date exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        AnimeInformationSection(
          item: _item(syncData: const {'awEndDate': '2024-06-01'}),
        ),
      ),
    );

    expect(find.text('بداية العرض'), findsOneWidget);
    expect(find.text('نهاية العرض'), findsOneWidget);
    expect(find.text('2024-06-01'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('hides duration when it is missing', (tester) async {
    await tester.pumpWidget(
      _app(
        AnimeInformationSection(
          item: _item(syncData: const {'awStudio': 'MAPPA'}),
        ),
      ),
    );

    expect(find.text('مدة الحلقة'), findsNothing);
    expect(find.text('الاستديو'), findsOneWidget);
  });

  testWidgets('details info card screenshots', (tester) async {
    await tester.runAsync(() async {
      const arabic =
          '/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf';
      if (!File(arabic).existsSync()) return;
      await (FontLoader('NotoSansArabic')
            ..addFont(File(arabic).readAsBytes().then(ByteData.sublistView))
            ..addFont(
              File(
                '/usr/share/fonts/truetype/noto/NotoSansArabic-Bold.ttf',
              ).readAsBytes().then(ByteData.sublistView),
            ))
          .load();
    });

    final artifacts = Directory('/opt/cursor/artifacts');
    if (!artifacts.existsSync()) return;

    Future<void> shot(String name, MultimediaItem item) async {
      await tester.pumpWidget(
        _app(
          RepaintBoundary(
            key: ValueKey(name),
            child: AnimeInformationSection(item: item),
          ),
          fontFamily: 'NotoSansArabic',
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(ValueKey(name)),
        );
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${artifacts.path}/$name.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    await shot(
      'details_info_no_source_no_dates',
      _item(
        source: 'AnimeWitcher',
        duration: 16,
        syncData: const {'awDuration': '16', 'awStudio': 'MAPPA'},
      ),
    );
    await shot(
      'details_info_start_date_only',
      _item(
        duration: 16,
        syncData: const {
          'awDuration': '16',
          'awStartDate': '2024-01-08',
          'awStudio': 'MAPPA',
        },
      ),
    );
  });
}
