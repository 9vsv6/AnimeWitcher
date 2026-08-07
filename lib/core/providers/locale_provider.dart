import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../storage/storage_service.dart';

part 'locale_provider.g.dart';

@Riverpod(keepAlive: true)
class LocaleNotifier extends _$LocaleNotifier {
  late final StorageService _storage;

  @override
  Locale build() {
    _storage = ref.read(storageServiceProvider);
    return _resolveLocale(_storage.getLanguage());
  }

  static Locale _resolveLocale(String langTag) {
    final languageCode = langTag.split('-').first.toLowerCase();
    return languageCode == 'ar' ? const Locale('ar') : const Locale('en');
  }

  Future<void> setLocale(Locale locale) async {
    final langTag = locale.countryCode != null
        ? '${locale.languageCode}-${locale.countryCode}'
        : locale.languageCode;
    await _storage.setLanguage(langTag);
    state = locale;
  }
}
