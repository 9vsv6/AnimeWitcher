import 'package:animewitcher/shared/widgets/paged_rail.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('secondary mouse drag scrolls a horizontal rail', (tester) async {
    final controller = ScrollController(initialScrollOffset: 100);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 120,
            child: PagedRail(
              controller: controller,
              itemExtent: 100,
              itemCount: 10,
              itemBuilder: (_, index) => ColoredBox(
                color: index.isEven ? Colors.red : Colors.blue,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.down(tester.getCenter(find.byType(PagedRail)));
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();

    expect(controller.offset, greaterThan(100));
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
