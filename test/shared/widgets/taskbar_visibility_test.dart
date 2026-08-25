import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:animewitcher/shared/widgets/taskbar_visibility.dart';

void main() {
  testWidgets('pushOverTaskbar covers a nested shell taskbar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () {
                    pushOverTaskbar<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          body: Text('overlay-page'),
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          bottomNavigationBar: const Text('taskbar'),
        ),
      ),
    );

    expect(find.text('taskbar'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('overlay-page'), findsOneWidget);
    expect(find.text('taskbar'), findsNothing);
  });

  testWidgets('nested Navigator.push leaves the shell taskbar visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          body: Text('nested-page'),
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          bottomNavigationBar: const Text('taskbar'),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('nested-page'), findsOneWidget);
    expect(find.text('taskbar'), findsOneWidget);
  });
}
