import 'package:flutter/material.dart';

/// Keeps player chrome and its overlay routes in the same physical order
/// regardless of the application's locale.
class PlayerLtr extends StatelessWidget {
  final Widget child;

  const PlayerLtr({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: child,
    );
  }
}

Future<T?> showPlayerDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? barrierColor,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: barrierColor,
    builder: (dialogContext) => PlayerLtr(
      child: builder(dialogContext),
    ),
  );
}
