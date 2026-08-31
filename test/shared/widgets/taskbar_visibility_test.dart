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

  testWidgets('showModalOverTaskbar covers the shell taskbar so actions stay tappable', (
    tester,
  ) async {
    var taskbarTaps = 0;
    var sheetActionTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          extendBody: true,
          body: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () {
                    showModalOverTaskbar<void>(
                      context: context,
                      builder: (_) => SizedBox(
                        height: 240,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: TextButton(
                            onPressed: () => sheetActionTaps++,
                            child: const Text('sheet-action'),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          bottomNavigationBar: SizedBox(
            height: 80,
            child: GestureDetector(
              onTap: () => taskbarTaps++,
              behavior: HitTestBehavior.opaque,
              child: const ColoredBox(
                color: Colors.red,
                child: Center(child: Text('taskbar')),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('sheet-action'), findsOneWidget);
    expect(find.text('taskbar'), findsOneWidget);

    await tester.tap(find.text('sheet-action'));
    await tester.pump();
    expect(sheetActionTaps, 1);
    expect(taskbarTaps, 0);
  });

  testWidgets('branch-navigator sheets leave the taskbar able to steal taps', (
    tester,
  ) async {
    var taskbarTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          extendBody: true,
          body: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      builder: (_) => const SizedBox(
                        height: 80,
                        child: Text('branch-sheet'),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          bottomNavigationBar: SizedBox(
            height: 80,
            child: GestureDetector(
              onTap: () => taskbarTaps++,
              behavior: HitTestBehavior.opaque,
              child: const ColoredBox(
                color: Colors.red,
                child: Center(child: Text('taskbar')),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('taskbar'));
    await tester.pump();
    expect(taskbarTaps, 1);
  });
}
