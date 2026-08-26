import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/features/details/presentation/widgets/premium_details_widgets.dart';

int _unixSecondsFromNow(Duration remaining) {
  return DateTime.now().toUtc().add(remaining).millisecondsSinceEpoch ~/ 1000;
}

Future<void> _pumpCountdown(WidgetTester tester, Duration remaining) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: NextAiringWidget(
              nextAiring: NextAiring(
                episode: 2,
                unixTime: _unixSecondsFromNow(remaining),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _disposeCountdown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  testWidgets('hides the days card and centers hours/minutes/seconds', (
    tester,
  ) async {
    await _pumpCountdown(
      tester,
      const Duration(hours: 22, minutes: 39, seconds: 22),
    );

    expect(find.text('يوم'), findsNothing);
    expect(find.byKey(const ValueKey('countdown-days')), findsNothing);
    expect(find.byKey(const ValueKey('countdown-hours')), findsOneWidget);
    expect(find.byKey(const ValueKey('countdown-minutes')), findsOneWidget);
    expect(find.byKey(const ValueKey('countdown-seconds')), findsOneWidget);

    final parent = tester.getRect(find.byType(NextAiringWidget));
    final hours = tester.getRect(find.byKey(const ValueKey('countdown-hours')));
    final seconds = tester.getRect(
      find.byKey(const ValueKey('countdown-seconds')),
    );
    expect((hours.left + seconds.right) / 2, closeTo(parent.center.dx, 2));
    expect(hours.left, greaterThan(parent.left + 16));
    expect(seconds.right, lessThan(parent.right - 16));

    await _disposeCountdown(tester);
  });

  testWidgets('keeps a 0-hour card when days remain', (tester) async {
    await _pumpCountdown(tester, const Duration(days: 1, minutes: 8));

    expect(find.byKey(const ValueKey('countdown-days')), findsOneWidget);
    expect(find.byKey(const ValueKey('countdown-hours')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('countdown-hours')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
    expect(find.text('00'), findsNothing);
    expect(find.byKey(const ValueKey('countdown-minutes')), findsOneWidget);
    expect(find.byKey(const ValueKey('countdown-seconds')), findsOneWidget);

    await _disposeCountdown(tester);
  });

  testWidgets('renders unit values without a leading zero', (tester) async {
    await _pumpCountdown(
      tester,
      const Duration(hours: 5, minutes: 7, seconds: 14),
    );

    expect(find.text('05'), findsNothing);
    expect(find.text('07'), findsNothing);
    expect(find.text('04'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('countdown-hours')),
        matching: find.text('5'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('countdown-minutes')),
        matching: find.text('7'),
      ),
      findsOneWidget,
    );

    await _disposeCountdown(tester);
  });

  testWidgets('hides days and hours when only minutes remain', (tester) async {
    await _pumpCountdown(tester, const Duration(minutes: 12, seconds: 5));

    expect(find.byKey(const ValueKey('countdown-days')), findsNothing);
    expect(find.byKey(const ValueKey('countdown-hours')), findsNothing);
    expect(find.byKey(const ValueKey('countdown-minutes')), findsOneWidget);
    expect(find.byKey(const ValueKey('countdown-seconds')), findsOneWidget);

    final parent = tester.getRect(find.byType(NextAiringWidget));
    final minutes = tester.getRect(
      find.byKey(const ValueKey('countdown-minutes')),
    );
    final seconds = tester.getRect(
      find.byKey(const ValueKey('countdown-seconds')),
    );
    expect((minutes.left + seconds.right) / 2, closeTo(parent.center.dx, 2));

    await _disposeCountdown(tester);
  });

  testWidgets('centers the seconds card when it is the only unit', (
    tester,
  ) async {
    await _pumpCountdown(tester, const Duration(seconds: 22));

    expect(find.byKey(const ValueKey('countdown-days')), findsNothing);
    expect(find.byKey(const ValueKey('countdown-hours')), findsNothing);
    expect(find.byKey(const ValueKey('countdown-minutes')), findsNothing);
    expect(find.byKey(const ValueKey('countdown-seconds')), findsOneWidget);

    final parent = tester.getRect(find.byType(NextAiringWidget));
    final seconds = tester.getRect(
      find.byKey(const ValueKey('countdown-seconds')),
    );
    expect(seconds.center.dx, closeTo(parent.center.dx, 2));

    await _disposeCountdown(tester);
  });
}
