import 'package:animewitcher/features/search/presentation/widgets/search_action_buttons.dart';
import 'package:animewitcher/shared/widgets/apple_liquid_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The phone's search bar is a field and a sort/filter group sharing one line.
/// They were built to two different heights — 42 and 48 — which reads as two
/// controls rather than one strip.
void main() {
  testWidgets('the field and the button group are the same height', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const height = 48.0;
    final fieldKey = UniqueKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              titleSpacing: 12,
              centerTitle: true,
              leadingWidth:
                  SearchActionButtons.groupWidthForHeight(height) + 10,
              leading: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Center(
                  heightFactor: 1,
                  child: SearchActionButtons(
                    sortValue: 'default',
                    sortItems: const <AppleNativeMenuItem>[
                      AppleNativeMenuItem(value: 'default', label: 'Default'),
                    ],
                    onSortSelected: (_) {},
                    onFilterPressed: () {},
                    sortTooltip: 'Sort',
                    filterTooltip: 'Filters',
                    sortIcon: Icons.swap_vert_rounded,
                    sortSystemImage: 'arrow.up.arrow.down',
                    height: height,
                  ),
                ),
              ),
              title: SizedBox(
                key: fieldKey,
                height: height,
                child: const TextField(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final field = tester.getRect(find.byKey(fieldKey));
    final group = tester.getRect(find.byType(SearchActionButtons));

    expect(field.height, group.height);
    // And both are on the same line, centred against each other rather than
    // one sitting higher than the other.
    expect(field.center.dy, closeTo(group.center.dy, 0.5));
    // 48 is the smallest a thumb should be asked to hit.
    expect(field.height, greaterThanOrEqualTo(48));
  });
}
