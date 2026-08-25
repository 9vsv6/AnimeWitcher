import 'package:flutter/widgets.dart';

/// The app ships Arabic-only. Kept as a helper so existing locale checks
/// continue to compile without branching on English.
bool isArabicAppLocale(BuildContext context) => true;

/// Returns [arabic]. [english] is ignored and kept only so existing call
/// sites do not need a mass rewrite.
String appText(
  BuildContext context, {
  required String english,
  required String arabic,
}) => arabic;
