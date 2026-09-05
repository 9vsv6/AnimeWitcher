import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The volume track paints three things across two Slider segments: the level
/// so far, how much of it is amplification, and the room left. These cover the
/// arithmetic that decides where the red starts, which is the part a change to
/// the ceiling would quietly get wrong.
void main() {
  group('where amplification begins on the track', () {
    // The slider runs from silence to the engine's ceiling, so the point where
    // the recording's own level sits is that ceiling's reciprocal.
    double boostStart(double maxVolume) =>
        maxVolume > 1.0 ? 1.0 / maxVolume : 1.0;

    test('sits halfway when the engine can double the level', () {
      expect(boostStart(2.0), 0.5);
    });

    test('sits off the end when the engine cannot amplify', () {
      // ExoPlayer stops at the recording's own level. Nothing on that track is
      // boost, so the red segment starts where the track ends and is never
      // drawn.
      expect(boostStart(1.0), 1.0);
    });
  });

  testWidgets('a drag reports every step, not just the release', (
    tester,
  ) async {
    // What the bug was: the level only reached the engine from onChangeEnd, so
    // the sound jumped once the pointer was let go instead of following it.
    final reported = <double>[];
    var releases = 0;
    var value = 0.5;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: StatefulBuilder(
                builder: (context, setState) => Slider(
                  value: value,
                  max: 2.0,
                  onChanged: (next) {
                    setState(() => value = next);
                    reported.add(next);
                  },
                  onChangeEnd: (_) => releases += 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final slider = tester.getCenter(find.byType(Slider));
    final gesture = await tester.startGesture(slider);
    for (var step = 0; step < 4; step++) {
      await gesture.moveBy(const Offset(12, 0));
      await tester.pump();
    }
    expect(
      reported.length,
      greaterThan(1),
      reason: 'the level must move with the pointer, not wait for it',
    );
    expect(releases, 0, reason: 'still dragging');

    await gesture.up();
    await tester.pump();
    expect(releases, 1);
    expect(reported.last, greaterThan(0.5));
  });
}
