import 'package:animewitcher/shared/widgets/recoverable_network_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('recovery state exposes retry, downloads, and pull refresh',
      (tester) async {
    var retryCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecoverableNetworkState(
            onRetry: () async {
              retryCalls += 1;
            },
          ),
        ),
      ),
    );

    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retryCalls, 1);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    expect(retryCalls, 2);
  });
}
