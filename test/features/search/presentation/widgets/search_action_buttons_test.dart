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
              leadingWidth: 94,
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
                  height: 42,
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

    // The entire right-hand 42px filter slot is intentionally tappable too.
    await tester.tapAt(Offset(groupRect.right - 2, groupRect.center.dy));
    await tester.pump();
    expect(filterPresses, 2);
  });
}
