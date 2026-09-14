from pathlib import Path


# 1) Download confirmation: show/copy the exact stream.url.
p = Path('lib/features/details/presentation/download_launcher.dart')
s = p.read_text()
old = "import 'package:flutter/material.dart';\n"
new = "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n"
assert old in s and "package:flutter/services.dart" not in s
s = s.replace(old, new, 1)
old = """                Text(l10n.sizeWithParam(metadata.sizeString)),
                const SizedBox(height: 16),
                Text(l10n.fileSaveLocationNotification),
"""
new = """                Text(l10n.sizeWithParam(metadata.sizeString)),
                const SizedBox(height: 12),
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    IconButton(
                      tooltip: appText(
                        ctx,
                        english: 'Copy link',
                        arabic: 'نسخ الرابط',
                      ),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: stream.url),
                        );
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
                          SnackBar(
                            content: Text(
                              appText(
                                ctx,
                                english: 'Link copied',
                                arabic: 'تم نسخ الرابط',
                              ),
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          stream.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(l10n.fileSaveLocationNotification),
"""
assert old in s
s = s.replace(old, new, 1)
p.write_text(s)


# 2) Account service: split fast local restore from network validation.
p = Path('lib/core/account/animewitcher_account_service.dart')
s = p.read_text()
start = s.index('  Future<AnimeWitcherAccountSnapshot> restoreSession() async {')
end = s.index('  Future<AnimeWitcherAccountSnapshot> signInWithEmail({', start)
replacement = r'''  /// Restores only the locally cached account state.
  ///
  /// This deliberately performs no network I/O so app startup can render the
  /// signed-in account immediately instead of waiting for Firebase/profile
  /// verification and a full sync on every launch.
  Future<AnimeWitcherAccountSnapshot> restoreCachedSession() async {
    final rawSession = await _secureStorage.read(_sessionKey);
    if (rawSession == null || rawSession.isEmpty) return snapshot;

    try {
      final restoredSession = AnimeWitcherSession.fromJson(
        Map<String, dynamic>.from(jsonDecode(rawSession) as Map),
      );
      AnimeWitcherProfile? restoredProfile;
      final rawProfile = await _secureStorage.read(_profileKey);
      if (rawProfile != null && rawProfile.isNotEmpty) {
        restoredProfile = AnimeWitcherProfile.fromJson(
          Map<String, dynamic>.from(jsonDecode(rawProfile) as Map),
        );
      }

      _session = restoredSession;
      _profile = restoredProfile;
      _sessionGeneration++;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[AnimeWitcherAccount] Cached restore failed: $error');
      }
      await _clearLocalSession();
      return snapshot;
    }

    final cachedProfile = _profile;
    try {
      _lastSyncAt = DateTime.tryParse(
        _storage.getString(
              cachedProfile == null
                  ? _legacyLastSyncKey
                  : _lastSyncKey(cachedProfile.uid),
            ) ??
            '',
      );
    } catch (error) {
      // The secure account cache is authoritative for startup. A settings-box
      // failure must not make a valid signed-in account disappear.
      _lastSyncAt = null;
      if (kDebugMode) {
        debugPrint(
          '[AnimeWitcherAccount] Cached sync timestamp unavailable: $error',
        );
      }
    }
    return snapshot;
  }

  /// Verifies a previously restored account and refreshes cloud-backed state.
  ///
  /// Callers may run this in the background after [restoreCachedSession].
  /// Generation checks prevent an old startup refresh from overwriting a user
  /// who signs out or switches accounts while network requests are in flight.
  Future<AnimeWitcherAccountSnapshot> refreshRestoredSession() async {
    if (_session == null) return snapshot;
    final generation = _sessionGeneration;

    try {
      final session = await _authorizedSession();
      if (generation != _sessionGeneration || _session == null) {
        return snapshot;
      }

      final user = await _auth.lookup(session.idToken);
      if (generation != _sessionGeneration || _session == null) {
        return snapshot;
      }

      if (session.signInMethod == AnimeWitcherSignInMethod.email &&
          user['emailVerified'] != true) {
        if (generation == _sessionGeneration) {
          await _clearLocalSession();
        }
        return snapshot;
      }

      final refreshedSession = session.copyWith(
        email: _optionalString(user['email']),
        displayName: _optionalString(user['displayName']),
        photoUrl: _optionalString(user['photoUrl']),
        providerIds: _providerIdsFromUser(user['providerUserInfo']),
      );
      final resolvedProfile = await _resolveProfile(
        refreshedSession,
        createIfMissing:
            refreshedSession.signInMethod == AnimeWitcherSignInMethod.google,
      );
      if (generation != _sessionGeneration || _session == null) {
        return snapshot;
      }

      _session = refreshedSession;
      _profile = resolvedProfile;
      await _persistSession();
      if (generation != _sessionGeneration || _session == null) {
        return snapshot;
      }
      _syncNewAuthEmailBestEffort(refreshedSession);
      await syncAll();
    } on AnimeWitcherAccountException catch (error) {
      if (error.code == 'invalid-session' ||
          error.code == 'account-not-found' ||
          error.code == 'profile-not-found' ||
          error.code == 'account-banned') {
        if (generation == _sessionGeneration) {
          await _clearLocalSession();
        }
      } else if (kDebugMode) {
        debugPrint('[AnimeWitcherAccount] Restore deferred: $error');
      }
    } catch (error) {
      // Keep a valid cached account visible while offline. All local features
      // remain available and the next manual/automatic sync retries safely.
      if (kDebugMode) {
        debugPrint('[AnimeWitcherAccount] Offline restore: $error');
      }
    }
    return snapshot;
  }

  /// Compatibility path for callers that explicitly require a fully verified
  /// restore before continuing.
  Future<AnimeWitcherAccountSnapshot> restoreSession() async {
    await restoreCachedSession();
    return refreshRestoredSession();
  }

'''
s = s[:start] + replacement + s[end:]

# Session invalidation must not fail just because the non-secure settings store
# is unavailable; secure tokens/profile are the critical data to clear.
old = """    await _secureStorage.delete(_sessionKey);
    await _secureStorage.delete(_profileKey);
    await _storage.remove(_legacyLastSyncKey);
"""
new = """    await _secureStorage.delete(_sessionKey);
    await _secureStorage.delete(_profileKey);
    try {
      await _storage.remove(_legacyLastSyncKey);
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[AnimeWitcherAccount] Failed to clear legacy sync timestamp: $error',
        );
      }
    }
"""
assert old in s
s = s.replace(old, new, 1)
p.write_text(s)


# 3) Riverpod controller: publish cache immediately; refresh later.
p = Path('lib/core/account/account_providers.dart')
s = p.read_text()
old = """  AnimeWitcherAccountService get _service =>
      ref.read(animeWitcherAccountServiceProvider);

  @override
  Future<AnimeWitcherAccountSnapshot> build() async {
    final restored = await _service.restoreSession();
    if (restored.isSignedIn) {
      unawaited(
        Future<void>.delayed(Duration.zero, () {
          ref.read(accountDataRevisionProvider.notifier).bump();
        }),
      );
    }
    return restored;
  }
"""
new = """  AnimeWitcherAccountService get _service =>
      ref.read(animeWitcherAccountServiceProvider);

  int _operationGeneration = 0;

  @override
  Future<AnimeWitcherAccountSnapshot> build() async {
    final startupGeneration = ++_operationGeneration;
    final restored = await _service.restoreCachedSession();
    if (restored.isSignedIn) {
      unawaited(
        Future<void>.delayed(Duration.zero, () {
          ref.read(accountDataRevisionProvider.notifier).bump();
        }),
      );
    }

    // Do not block the More screen behind Firebase lookup/profile resolution
    // and a full sync on every app launch. The cached account is usable now;
    // validation still runs immediately in the background.
    unawaited(
      Future<void>.delayed(Duration.zero, () async {
        final refreshed = await _service.refreshRestoredSession();
        if (startupGeneration != _operationGeneration) return;
        state = AsyncData(refreshed);
        ref.read(accountDataRevisionProvider.notifier).bump();
      }),
    );
    return restored;
  }
"""
assert old in s
s = s.replace(old, new, 1)
old = """  Future<void> _run(
    Future<AnimeWitcherAccountSnapshot> Function() operation, {
    bool bumpData = true,
  }) async {
    final previous = state.asData?.value ?? _service.snapshot;
"""
new = """  Future<void> _run(
    Future<AnimeWitcherAccountSnapshot> Function() operation, {
    bool bumpData = true,
  }) async {
    _operationGeneration++;
    final previous = state.asData?.value ?? _service.snapshot;
"""
assert old in s
s = s.replace(old, new, 1)
p.write_text(s)
