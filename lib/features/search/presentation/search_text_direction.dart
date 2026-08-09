import 'package:flutter/widgets.dart';

/// Chooses the search field direction from the first strong script character.
///
/// Arabic input is rendered right-to-left and English/Latin input left-to-right.
/// Neutral characters (spaces, punctuation, numbers, emoji) do not force a
/// direction, so an empty/neutral query keeps the surrounding UI direction.
TextDirection searchTextDirection(
  String text, {
  required TextDirection fallback,
}) {
  for (final rune in text.runes) {
    if (_isArabicRune(rune)) return TextDirection.rtl;
    if (_isLatinRune(rune)) return TextDirection.ltr;
  }
  return fallback;
}

bool _isArabicRune(int rune) {
  return (rune >= 0x0600 && rune <= 0x06FF) ||
      (rune >= 0x0750 && rune <= 0x077F) ||
      (rune >= 0x0870 && rune <= 0x089F) ||
      (rune >= 0x08A0 && rune <= 0x08FF) ||
      (rune >= 0xFB50 && rune <= 0xFDFF) ||
      (rune >= 0xFE70 && rune <= 0xFEFF);
}

bool _isLatinRune(int rune) {
  return (rune >= 0x0041 && rune <= 0x005A) ||
      (rune >= 0x0061 && rune <= 0x007A);
}
