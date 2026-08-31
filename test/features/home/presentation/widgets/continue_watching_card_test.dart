import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/core/storage/history_repository.dart';
import 'package:animewitcher/features/details/presentation/playback_launcher.dart';
import 'package:animewitcher/features/home/presentation/widgets/continue_watching_card.dart';
import 'package:animewitcher/features/library/presentation/history_provider.dart';
import 'package:animewitcher/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

HistoryItem _historyItem() {
  return HistoryItem(
    item: MultimediaItem(
      title: 'Buchigire Reijou wa Houfuku wo Chikaimashita',
      url: 'https://animewitcher.test/watch/abc',
      posterUrl: '',
      contentType: MultimediaContentType.anime,
      provider: 'fake.provider',
    ),
    position: 40,
    duration: 100,
    lastEpisodeUrl: 'abc|ep9',
    episode: 9,
    episodeServerName: 'الحلقة 9',
    timestamp: 0,
  );
}

class _RecordingPlaybackLauncher extends PlaybackLauncher {
  _RecordingPlaybackLauncher(super.ref);

  HistoryItem? played;
  int playCalls = 0;

  @override
  Future<void> playFromContinueWatching(
    BuildContext context,
    HistoryItem history,
  ) async {
    playCalls += 1;
    played = history;
  }
}

class _FakeContinueWatching extends ContinueWatchingNotifier {
  final List<String> removed = <String>[];

  @override
  List<HistoryItem> build() => const <HistoryItem>[];

  @override
  Future<void> remove(String url) async {
    removed.add(url);
  }
}

Widget _shell({
  required List<Override> overrides,
  required Widget child,
  VoidCallback? onTaskbarTap,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      locale: const Locale('ar'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(primary: Color(0xFFEEC60A)),
      ),
      home: Scaffold(
        extendBody: true,
        body: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => Center(
              child: SizedBox(width: 280, height: 150, child: child),
            ),
          ),
        ),
        bottomNavigationBar: SizedBox(
          height: 80,
          child: GestureDetector(
            onTap: onTaskbarTap,
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
}

void main() {
  testWidgets('tap opens continue-watching playback without leaving home', (
    tester,
  ) async {
    late _RecordingPlaybackLauncher recorder;
    final history = _historyItem();

    await tester.pumpWidget(
      _shell(
        overrides: [
          playbackLauncherProvider.overrideWith((ref) {
            recorder = _RecordingPlaybackLauncher(ref);
            return recorder;
          }),
        ],
        child: ContinueWatchingCard(historyItem: history),
      ),
    );

    await tester.tap(find.byType(ContinueWatchingCard));
    await tester.pump();

    expect(recorder.playCalls, 1);
    expect(recorder.played?.lastEpisodeUrl, 'abc|ep9');
    expect(find.text('عرض التفاصيل'), findsNothing);
    expect(find.text('taskbar'), findsOneWidget);
  });

  testWidgets('long-press menu appears above the taskbar and keeps its actions', (
    tester,
  ) async {
    var taskbarTaps = 0;
    final continueWatching = _FakeContinueWatching();
    final history = _historyItem();

    await tester.pumpWidget(
      _shell(
        overrides: [
          continueWatchingProvider.overrideWith(() => continueWatching),
        ],
        onTaskbarTap: () => taskbarTaps++,
        child: ContinueWatchingCard(historyItem: history),
      ),
    );

    await tester.longPress(find.byType(ContinueWatchingCard));
    await tester.pumpAndSettle();

    expect(find.text('عرض التفاصيل'), findsOneWidget);
    expect(find.text('إزالة من السجل'), findsOneWidget);
    expect(find.text('إلغاء'), findsOneWidget);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    expect(find.text('إلغاء'), findsNothing);
    expect(taskbarTaps, 0);
  });

  testWidgets('long-press remove still deletes the continue-watching item', (
    tester,
  ) async {
    late _FakeContinueWatching continueWatching;
    final history = _historyItem();

    await tester.pumpWidget(
      _shell(
        overrides: [
          continueWatchingProvider.overrideWith(() {
            continueWatching = _FakeContinueWatching();
            return continueWatching;
          }),
        ],
        child: ContinueWatchingCard(historyItem: history),
      ),
    );

    await tester.longPress(find.byType(ContinueWatchingCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إزالة من السجل'));
    await tester.pumpAndSettle();

    expect(continueWatching.removed, <String>[history.item.url]);
    expect(find.text('إزالة من السجل'), findsNothing);
  });
}
