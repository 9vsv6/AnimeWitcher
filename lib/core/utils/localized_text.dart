import 'package:flutter/widgets.dart';

bool isArabicAppLocale(BuildContext context) =>
    Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';

String appText(
  BuildContext context, {
  required String english,
  required String arabic,
}) => isArabicAppLocale(context) ? arabic : english;
