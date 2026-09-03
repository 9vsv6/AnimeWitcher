import 'package:animewitcher/shared/widgets/secondary_mouse_refresh_indicator.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('secondary mouse pull from the top refreshes once', (
    tester,
  ) async {
    var refreshCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SecondaryMouseRefreshIndicator(
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

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.down(const Offset(200, 100));
    await gesture.moveBy(const Offset(0, 90));
    await tester.pump(const Duration(milliseconds: 500));

    expect(refreshCount, 1);
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
