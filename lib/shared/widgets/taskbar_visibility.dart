import 'package:flutter/widgets.dart';

/// Pushes [route] on the root navigator so it covers [AppScaffold] and the
/// bottom taskbar. This is the same stack used by [DetailsRoute] and
/// [ViewAllRoute], and by More-tab screens.
Future<T?> pushOverTaskbar<T>(BuildContext context, Route<T> route) {
  return Navigator.of(context, rootNavigator: true).push<T>(route);
}
