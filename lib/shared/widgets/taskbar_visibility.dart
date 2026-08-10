import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Counts routes that temporarily own the full mobile canvas and therefore hide
/// the root taskbar. A depth counter keeps nested pushes safe.
final ValueNotifier<int> appTaskbarHiddenDepth = ValueNotifier<int>(0);

Future<T?> pushWithTaskbarHidden<T>(BuildContext context, Route<T> route) async {
  appTaskbarHiddenDepth.value += 1;
  try {
    return await Navigator.of(context).push<T>(route);
  } finally {
    appTaskbarHiddenDepth.value =
        appTaskbarHiddenDepth.value > 0 ? appTaskbarHiddenDepth.value - 1 : 0;
  }
}
