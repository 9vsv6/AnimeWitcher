import 'package:animewitcher/features/details/presentation/widgets/download_progress_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _PopObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

void main() {
  testWidgets('missing progress closes only the dialog route', (tester) async {
    final observer = _PopObserver();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorObservers: [observer],
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => DownloadProgressDialog.show(
                  context,
                  'Episode 1',
                  'missing-tracking-url',
                ),
                child: const Text('Anime details'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Anime details'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Anime details'), findsOneWidget);
    expect(observer.popCount, 1);
  });
}
