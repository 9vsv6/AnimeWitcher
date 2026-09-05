import 'package:animewitcher/shared/widgets/paged_rail.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a held mouse drag scrolls a horizontal rail', (tester) async {
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
              itemBuilder: (_, index) =>
                  ColoredBox(color: index.isEven ? Colors.red : Colors.blue),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(tester.getCenter(find.byType(PagedRail)));
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();

    expect(controller.offset, greaterThan(100));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a card still opens on a click that does not travel', (
    tester,
  ) async {
    // The rail scrolls on the same button a card is opened with, so the two
    // have to be told apart by whether the pointer moved. A recognizer drops
    // its tap once the pointer travels past the slop, which for a mouse is a
    // hair's width - so a click opens the card and a drag does not.
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final tapped = <int>[];

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
              itemBuilder: (_, index) => GestureDetector(
                onTap: () => tapped.add(index),
                child: ColoredBox(
                  color: index.isEven ? Colors.red : Colors.blue,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final centre = tester.getCenter(find.byType(PagedRail));

    final click = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await click.down(centre);
    await click.up();
    await tester.pumpAndSettle();
    expect(tapped, isNotEmpty, reason: 'a plain click must still open a card');

    tapped.clear();
    final drag = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await drag.down(centre);
    await drag.moveBy(const Offset(-60, 0));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(
      tapped,
      isEmpty,
      reason: 'a drag scrolls the rail, it does not open',
    );
    expect(controller.offset, greaterThan(0));
  });
}
