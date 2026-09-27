import 'package:flutter/widgets.dart';

/// Returns [arabic]. [english] is ignored and kept only so existing call
/// sites do not need a mass rewrite.
String appText(
  BuildContext context, {
  required String english,
  required String arabic,
}) => arabic;
