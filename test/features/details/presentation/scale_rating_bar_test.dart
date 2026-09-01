import 'package:animewitcher/features/details/presentation/widgets/scale_rating_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('leftmost star is 1 and rightmost is 10 on an RTL page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: ScaleRatingBar(
                rating: 0,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final first = tester.getRect(find.bySemanticsLabel('1'));
    final tenth = tester.getRect(find.bySemanticsLabel('10'));
    expect(first.left, lessThan(tenth.left));
  });

  testWidgets('only the tapped star scales during the bounce', (tester) async {
    var rating = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: Center(
                child: ScaleRatingBar(
                  rating: rating,
                  onChanged: (value) => setState(() => rating = value),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('7'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final scales = tester
        .widgetList<Transform>(find.byType(Transform))
        .map((transform) => transform.transform.getMaxScaleOnAxis())
        .toList(growable: false);
    expect(scales.where((scale) => scale > 1.01), hasLength(1));
  });
}
