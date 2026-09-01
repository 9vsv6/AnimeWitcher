import 'package:flutter/material.dart';

/// Pushes [route] on the root navigator so it covers [AppScaffold] and the
/// bottom taskbar. This is the same stack used by [DetailsRoute] and
/// [ViewAllRoute], and by More-tab screens.
Future<T?> pushOverTaskbar<T>(BuildContext context, Route<T> route) {
  return Navigator.of(context, rootNavigator: true).push<T>(route);
}

/// Shows a modal bottom sheet on the root navigator so it covers the floating
/// pill taskbar. Branch-navigator sheets paint underneath [AppScaffold]'s
/// `bottomNavigationBar` and hide Cancel / the last server row.
Future<T?> showModalOverTaskbar<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = false,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: isScrollControlled,
    showDragHandle: showDragHandle,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    builder: builder,
  );
}
