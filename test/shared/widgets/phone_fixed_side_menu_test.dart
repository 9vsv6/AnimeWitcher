import 'package:animewitcher/core/navigation/taskbar_destination.dart';
import 'package:animewitcher/features/search/presentation/search_domain.dart';
import 'package:animewitcher/l10n/generated/app_localizations.dart';
import 'package:animewitcher/shared/widgets/app_side_menu.dart';
import 'package:animewitcher/shared/widgets/phone_fixed_side_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('phone side menu has one fixed product order and group breaks', (
    tester,
  ) async {
    late List<AppSideMenuEntry> entries;
    final picked = <TaskbarDestination>[];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              entries = phoneFixedSideMenuEntries(
                context,
                ref,
                currentBranchIndex: TaskbarDestination.home.branchIndex,
                onDestination: picked.add,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(
      entries.map((entry) => entry.id),
      <String>[
        'home',
        'anime-search',
        'manga-search',
        'animation-search',
        'seasons',
        'global-statistics',
        'coming-soon',
        'library',
        'favorite-characters',
        'recent-watched',
        'characters-search',
        'broadcast-schedule',
        'news',
      ],
    );
    expect(
      entries.where((entry) => entry.dividerBefore).map((entry) => entry.id),
      <String>['global-statistics', 'library', 'characters-search'],
    );
    expect(entries.first.selected, isTrue);
    expect(entries.map((entry) => entry.label), containsAllInOrder(<String>[
      'الرئيسية',
      'الأنمي',
      'المانجا',
      'الانميشن',
      'المواسم',
      'الإحصائيات العالمية',
      'القادم قريبًا',
      'المكتبة',
      'الشخصيات المفضلة',
      'آخر المشاهدات',
      'الشخصيات',
      'جدول الحلقات',
      'الأخبار',
    ]));
  });

  testWidgets('search rows switch the search domain before opening Search', (
    tester,
  ) async {
    final picked = <TaskbarDestination>[];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              final entries = phoneFixedSideMenuEntries(
                context,
                ref,
                currentBranchIndex: TaskbarDestination.home.branchIndex,
                onDestination: picked.add,
              );
              final manga = entries.firstWhere(
                (entry) => entry.id == 'manga-search',
              );
              final characters = entries.firstWhere(
                (entry) => entry.id == 'characters-search',
              );
              return Column(
                children: [
                  Text(
                    ref.watch(searchDomainProvider).name,
                    key: const ValueKey<String>('domain'),
                  ),
                  TextButton(
                    key: const ValueKey<String>('entry-manga-search'),
                    onPressed: manga.onTap,
                    child: const Text('manga-search'),
                  ),
                  TextButton(
                    key: const ValueKey<String>('entry-characters-search'),
                    onPressed: characters.onTap,
                    child: const Text('characters-search'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('entry-manga-search')));
    await tester.pump();
    expect(find.text('manga'), findsOneWidget);
    expect(picked, <TaskbarDestination>[TaskbarDestination.search]);

    await tester.tap(
      find.byKey(const ValueKey<String>('entry-characters-search')),
    );
    await tester.pump();
    expect(find.text('characters'), findsOneWidget);
    expect(
      picked,
      <TaskbarDestination>[
        TaskbarDestination.search,
        TaskbarDestination.search,
      ],
    );
  });
}
