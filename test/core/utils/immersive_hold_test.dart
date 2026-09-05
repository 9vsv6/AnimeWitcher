import 'package:animewitcher/core/utils/immersive_mode.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    debugImmersivePlatformOverride = ImmersivePlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method.startsWith('SystemChrome.')) calls.add(call);
          return null;
        });
  });

  tearDown(() {
    cancelImmersiveHold();
    debugImmersivePlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  List<MethodCall> modeCalls() => calls
      .where((call) => call.method == 'SystemChrome.setEnabledSystemUIMode')
      .toList();

  testWidgets('full screen is asked for again when the window changes shape', (
    tester,
  ) async {
    // Closing the player puts the orientation back, and the window that comes
    // back from that carries the bars in their default state. Asking once is
    // not enough: the request lands and is then wiped.
    holdImmersiveFullScreen(true);
    await tester.pump();
    expect(modeCalls().length, 1);
    expect(modeCalls().single.arguments, contains('immersiveSticky'));

    // The rotation lands.
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pump();

    expect(
      modeCalls().length,
      2,
      reason: 'the choice must be re-asserted after the relayout',
    );
    expect(modeCalls().last.arguments, contains('immersiveSticky'));
    cancelImmersiveHold();
  });

  testWidgets('the hold lets go, and stops answering afterwards', (
    tester,
  ) async {
    holdImmersiveFullScreen(true);
    await tester.pump();
    final before = modeCalls().length;

    await tester.pump(immersiveHoldWindow + const Duration(seconds: 1));

    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pump();

    expect(
      modeCalls().length,
      before,
      reason: 'a rotation long after leaving is not the player\'s business',
    );
  });

  testWidgets('a later hold replaces the one before it', (tester) async {
    holdImmersiveFullScreen(true);
    await tester.pump();
    holdImmersiveFullScreen(false);
    await tester.pump();
    calls.clear();

    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pump();

    // Only the newer choice answers, and it is the one that shows the bars.
    expect(modeCalls(), isNotEmpty);
    expect(
      modeCalls().any(
        (call) => '${call.arguments}'.contains('immersiveSticky'),
      ),
      isFalse,
    );
    cancelImmersiveHold();
  });

  testWidgets('nothing is held off a phone', (tester) async {
    debugImmersivePlatformOverride = null;
    holdImmersiveFullScreen(true);
    await tester.pump();

    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pump();

    expect(calls, isEmpty);
  });
}
