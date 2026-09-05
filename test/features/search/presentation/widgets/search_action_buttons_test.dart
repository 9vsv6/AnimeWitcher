import 'package:animewitcher/features/search/presentation/widgets/search_action_buttons.dart';
import 'package:animewitcher/shared/widgets/apple_liquid_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('filter hitbox stays aligned with the icon in an RTL AppBar', (
    tester,
  ) async {
    var filterPresses = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(
              leadingWidth: 106,
              leading: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: SearchActionButtons(
                  sortValue: 'default',
                  sortItems: const <AppleNativeMenuItem>[
                    AppleNativeMenuItem(value: 'default', label: 'Default'),
                  ],
                  onSortSelected: (_) {},
                  onFilterPressed: () => filterPresses += 1,
                  sortTooltip: 'Sort',
                  filterTooltip: 'Filters',
                  sortIcon: Icons.swap_vert_rounded,
                  sortSystemImage: 'arrow.up.arrow.down',
                  height: 48,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    final groupRect = tester.getRect(find.byType(SearchActionButtons));
    final filterIconRect = tester.getRect(find.byIcon(Icons.tune_rounded));

    // Tapping the pixels that paint the icon must activate the filter itself.
    await tester.tapAt(filterIconRect.center);
    await tester.pump();
    expect(filterPresses, 1);

    // The entire right-hand 48px filter slot is intentionally tappable too.
    await tester.tapAt(Offset(groupRect.right - 2, groupRect.center.dy));
    await tester.pump();
    expect(filterPresses, 2);

    // Include all corners of the AppBar slot, outside the small painted glyph.
    for (final point in [
      Offset(groupRect.right - 47, groupRect.top + 1),
      Offset(groupRect.right - 1, groupRect.top + 1),
      Offset(groupRect.right - 47, groupRect.bottom - 1),
      Offset(groupRect.right - 1, groupRect.bottom - 1),
    ]) {
      await tester.tapAt(point);
      await tester.pump();
    }
    expect(filterPresses, 6);
  });

  testWidgets('alphabetical orders are spelled out in the sort menu', (
    tester,
  ) async {
    var picked = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(
              leading: SearchActionButtons(
                sortValue: 'favorites',
                sortItems: const <AppleNativeMenuItem>[
                  AppleNativeMenuItem(
                    value: 'favorites',
                    label: 'Most favorited',
                    systemImage: 'star.fill',
                  ),
                  AppleNativeMenuItem(
                    value: 'name_asc',
                    label: 'Name A to Z',
                    systemImage: 'animewitcher.abc',
                  ),
                  AppleNativeMenuItem(
                    value: 'name_desc',
                    label: 'Name Z to A',
                    systemImage: 'animewitcher.zyx',
                  ),
                ],
                onSortSelected: (value) => picked = value,
                onFilterPressed: () {},
                sortTooltip: 'Sort',
                filterTooltip: 'Filters',
                sortIcon: Icons.swap_vert_rounded,
                sortSystemImage: 'star.fill',
                height: 48,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();

    // The two alphabetical orders read as letters rather than as an icon.
    expect(find.text('ABC'), findsOneWidget);
    expect(find.text('ZYX'), findsOneWidget);

    // And the menu still reports what was chosen, which it does by hand now
    // that the rows live inside one disabled popup item.
    await tester.tap(find.text('Name Z to A'));
    await tester.pumpAndSettle();
    expect(picked, 'name_desc');
  });
}
