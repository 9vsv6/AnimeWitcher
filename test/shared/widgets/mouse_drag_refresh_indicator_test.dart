import 'package:animewitcher/shared/widgets/mouse_drag_refresh_indicator.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a held mouse drag from the top refreshes once', (
    tester,
  ) async {
    var refreshCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MouseDragRefreshIndicator(
            onRefresh: () async {
              refreshCount++;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [SizedBox(height: 900)],
            ),
          ),
        ),
      ),
    );

    final listener = tester.widget<Listener>(
      find.byKey(mouseDragRefreshListenerKey),
    );
    listener.onPointerDown!(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        position: Offset(200, 100),
        buttons: kPrimaryMouseButton,
      ),
    );
    listener.onPointerMove!(
      const PointerMoveEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        position: Offset(200, 190),
        delta: Offset(0, 90),
        buttons: kPrimaryMouseButton,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(refreshCount, 1);
    await tester.pumpAndSettle();
  });
}
