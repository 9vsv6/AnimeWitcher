import 'package:flutter/material.dart';

/// The app's compact search field used by Library and Search.
///
/// Keep the visual contract here so both screens stay pixel-identical.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.fieldKey,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.suffixIcon,
    this.textDirection,
  });

  static const double height = 42;

  final Key? fieldKey;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffixIcon;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final field = TextField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textDirection: textDirection,
      textAlign: TextAlign.start,
      textAlignVertical: TextAlignVertical.center,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.6),
        contentPadding: EdgeInsets.zero,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(99),
          borderSide: BorderSide.none,
        ),
      ),
    );

    return SizedBox(
      height: height,
      child: textDirection == null
          ? field
          : Directionality(textDirection: textDirection!, child: field),
    );
  }
}
