import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persistent Liquid Glass visibility uses gentle native motion', () {
    final dartSource = File(
      'lib/shared/widgets/apple_liquid_glass.dart',
    ).readAsStringSync();
    final swiftSource = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(
      dartSource,
      contains("'instantVisibilityChanges': false"),
      reason:
          'Details boundaries may hard-cut toolbar content, but the glass itself should still animate in and out.',
    );
    expect(
      swiftSource,
      contains('UIAccessibility.isReduceMotionEnabled'),
      reason: 'native Liquid Glass motion must respect Reduce Motion',
    );
    expect(
      swiftSource,
      contains('liquidGlassHiddenScale'),
      reason: 'appearance/disappearance should include the approved soft scale',
    );
    expect(
      swiftSource,
      contains('usingSpringWithDamping'),
      reason: 'appearance should use a gentle spring rather than an instant jump',
    );
    expect(
      swiftSource,
      isNot(contains('withDuration: 0.035')),
      reason: 'the old 35ms disappearance was effectively an abrupt cut',
    );
  });

  test('toolbar geometry morphs together with structural item changes', () {
    final swiftSource = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(
      swiftSource,
      contains('toolbarGeometryAnimationDuration'),
      reason:
          'the toolbar capsule needs an explicit geometry animation instead of snapping its constraints before the item morph',
    );
    expect(
      swiftSource,
      contains('private func applyToolbarGeometry('),
      reason:
          'width and trailing inset should be committed by one shared geometry transition',
    );
    expect(
      swiftSource,
      contains(
        'options: [.beginFromCurrentState, .curveEaseInOut, .allowUserInteraction]',
      ),
      reason:
          'interactive push/pop reversals must continue from the current toolbar position',
    );
    expect(
      swiftSource,
      contains('trailingConstant: targetToolbarTrailingConstant'),
      reason:
          'the 8pt Comments inset and 34pt Anime/Character inset must transition with the same toolbar morph',
    );
  });
}
