import 'dart:async';

import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../storage/storage_service.dart';

part 'locale_provider.g.dart';

/// App UI is Arabic-only. English is no longer a selectable locale.
const Locale kAppLocale = Locale('ar');

@Riverpod(keepAlive: true)
class LocaleNotifier extends _$LocaleNotifier {
  late final StorageService _storage;

  @override
  Locale build() {
    _storage = ref.read(storageServiceProvider);
    if (_storage.getLanguage() != 'ar') {
      unawaited(_storage.setLanguage('ar'));
    }
    return kAppLocale;
  }

  Future<void> setLocale(Locale locale) async {
    await _storage.setLanguage('ar');
    state = kAppLocale;
  }
}
