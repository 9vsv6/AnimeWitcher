/// Replaces Arabic-Indic and Eastern Arabic-Indic digits with ASCII digits.
String normalizeLocalizedDigits(String value) {
  const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  const easternArabicIndic = '۰۱۲۳۴۵۶۷۸۹';
  return value
      .replaceAllMapped(
        RegExp(r'[٠-٩]'),
        (match) => '${arabicIndic.indexOf(match.group(0)!)}',
      )
      .replaceAllMapped(
        RegExp(r'[۰-۹]'),
        (match) => '${easternArabicIndic.indexOf(match.group(0)!)}',
      );
}
