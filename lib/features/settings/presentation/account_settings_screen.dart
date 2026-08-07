import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/layout_constants.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

import 'widgets/settings_widgets.dart';
import 'widgets/settings_dialogs.dart';
import 'widgets/webview_auth_dialog.dart';
import 'player_settings_provider.dart';

import '../../../core/config/sync_config.dart';
import '../../tracking/presentation/tracking_auth_provider.dart';
import '../../tracking/data/mal_service.dart';
import '../../tracking/data/anilist_service.dart';
import '../../../core/storage/settings_repository.dart';

import 'package:skystream/core/utils/localized_text.dart';
class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  ConsumerState<AccountSettingsScreen> createState() =>
      _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen> {
  final FocusNode _malFocusNode = FocusNode();
  final FocusNode _anilistFocusNode = FocusNode();

  @override
  void dispose() {
    _malFocusNode.dispose();
    _anilistFocusNode.dispose();
    super.dispose();
  }

  Future<bool> _confirmDisconnect(
    BuildContext context,
    String providerName,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          appText(
            context,
            english: 'Disconnect $providerName',
            arabic: 'قطع الاتصال بـ $providerName',
          ),
        ),
        content: Text(
          appText(
            context,
            english:
                'Are you sure you want to disconnect your $providerName account?',
            arabic: 'هل تريد بالتأكيد قطع اتصال حساب $providerName؟',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              appText(context, english: 'Disconnect', arabic: 'قطع الاتصال'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final playerSettings =
        ref.watch(playerSettingsProvider).asData?.value ??
        const PlayerSettings();
    final settingsRepo = ref.watch(settingsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.accounts)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.only(bottom: LayoutConstants.spacingLg),
            children: [
              const SizedBox(height: LayoutConstants.spacingXs),
              SettingsGroup(
                title: l10n.accounts,
                children: [
                  SettingsTile(
                    icon: Icons.subtitles_rounded,
                    title: l10n.openSubtitles,
                    subtitle: playerSettings.osUsername.isNotEmpty
                        ? l10n.loggedInAs(playerSettings.osUsername)
                        : l10n.notLoggedIn,
                    onTap: () => showOpenSubtitlesAuthDialog(
                      context,
                      ref,
                      playerSettings,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.vpn_key_rounded,
                    title: l10n.subDl,
                    subtitle: playerSettings.subdlApiKey.isNotEmpty
                        ? l10n.apiKeyConfigured
                        : l10n.keyNotSet,
                    onTap: () =>
                        showSubDlAuthDialog(context, ref, playerSettings),
                  ),
                  SettingsTile(
                    icon: Icons.vpn_key_rounded,
                    title: l10n.subSource,
                    subtitle: playerSettings.subsourceApiKey.isNotEmpty
                        ? l10n.apiKeyConfigured
                        : l10n.keyNotSet,
                    onTap: () =>
                        showSubSourceAuthDialog(context, ref, playerSettings),
                  ),
                  Consumer(
                    builder: (context, ref, _) {
                      final trackingAuthAsync = ref.watch(trackingAuthProvider);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SettingsTile(
                            focusNode: _malFocusNode,
                            icon: Icons.sync_rounded,
                            title: 'MyAnimeList',
                            subtitle: trackingAuthAsync.when(
                              data: (state) => state['mal'] == true
                                  ? appText(context, english: 'Connected', arabic: 'متصل')
                                  : l10n.notLoggedIn,
                              loading: () => l10n.loading,
                              error: (_, _) => l10n.unknown,
                            ),
                            onTap: () async {
                              final state = trackingAuthAsync.value ?? {};
                              if (state['mal'] == true) {
                                final confirm = await _confirmDisconnect(
                                  context,
                                  'MyAnimeList',
                                );
                                if (confirm) {
                                  await ref.read(malServiceProvider).logout();
                                  ref.invalidate(trackingAuthProvider);
                                  if (context.mounted) {
                                    _malFocusNode.requestFocus();
                                  }
                                }
                              } else {
                                final malService = ref.read(malServiceProvider);
                                // Generate PKCE verifier before opening webview
                                final codeVerifier = malService
                                    .generateCodeVerifier();

                                final authUrl =
                                    'https://myanimelist.net/v1/oauth2/authorize'
                                    '?response_type=code'
                                    '&client_id=${SyncConfig.malClientId}'
                                    '&code_challenge=$codeVerifier'
                                    '&code_challenge_method=plain'
                                    '&redirect_uri=${Uri.encodeComponent('http://localhost')}';

                                if (context.mounted) {
                                  final redirectUrl = await showDialog<String>(
                                    context: context,
                                    builder: (context) => WebViewAuthDialog(
                                      providerName: 'MyAnimeList',
                                      initialUrl: authUrl,
                                      redirectUrlPrefix: 'http://localhost',
                                    ),
                                  );

                                  if (redirectUrl != null && context.mounted) {
                                    final success = await malService
                                        .exchangeCodeForToken(
                                          redirectUrl,
                                          codeVerifier,
                                        );
                                    if (success && context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            appText(context, english: 'Successfully connected to MyAnimeList!', arabic: 'تم الاتصال بـ MyAnimeList بنجاح!'),
                                          ),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    } else if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            appText(context, english: 'Failed to connect to MyAnimeList', arabic: 'فشل الاتصال بـ MyAnimeList'),
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                  if (context.mounted) {
                                    _malFocusNode.requestFocus();
                                  }
                                }
                              }
                              ref.invalidate(trackingAuthProvider);
                            },
                          ),
                          SettingsTile(
                            focusNode: _anilistFocusNode,
                            icon: Icons.sync_rounded,
                            title: 'AniList',
                            subtitle: trackingAuthAsync.when(
                              data: (state) => state['anilist'] == true
                                  ? appText(context, english: 'Connected', arabic: 'متصل')
                                  : l10n.notLoggedIn,
                              loading: () => l10n.loading,
                              error: (_, _) => l10n.unknown,
                            ),
                            isLast: true,
                            onTap: () async {
                              final state = trackingAuthAsync.value ?? {};
                              if (state['anilist'] == true) {
                                final confirm = await _confirmDisconnect(
                                  context,
                                  'AniList',
                                );
                                if (confirm) {
                                  await ref
                                      .read(aniListServiceProvider)
                                      .logout();
                                  ref.invalidate(trackingAuthProvider);
                                  if (context.mounted) {
                                    _anilistFocusNode.requestFocus();
                                  }
                                }
                              } else {
                                final anilistService = ref.read(
                                  aniListServiceProvider,
                                );

                                const authUrl =
                                    'https://anilist.co/api/v2/oauth/authorize'
                                    '?client_id=${SyncConfig.anilistClientId}'
                                    '&response_type=token';

                                if (context.mounted) {
                                  final redirectUrl = await showDialog<String>(
                                    context: context,
                                    builder: (context) =>
                                        const WebViewAuthDialog(
                                          providerName: 'AniList',
                                          initialUrl: authUrl,
                                          redirectUrlPrefix: 'http://localhost',
                                        ),
                                  );

                                  if (redirectUrl != null && context.mounted) {
                                    final success = await anilistService
                                        .saveTokenFromRedirect(redirectUrl);
                                    if (success && context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            appText(context, english: 'Successfully connected to AniList!', arabic: 'تم الاتصال بـ AniList بنجاح!'),
                                          ),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    } else if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            appText(context, english: 'Failed to connect to AniList', arabic: 'فشل الاتصال بـ AniList'),
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                  if (context.mounted) {
                                    _anilistFocusNode.requestFocus();
                                  }
                                }
                              }
                              ref.invalidate(trackingAuthProvider);
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: LayoutConstants.spacingLg),
              SettingsGroup(
                title: appText(context, english: 'Integrations', arabic: 'التكاملات'),
                children: [
                  SettingsTile(
                    icon: Icons.fast_forward_rounded,
                    title: 'AnimeSkip',
                    isBeta: true,
                    subtitle: appText(
                      context,
                      english:
                          'Automatically fetch skip segments for Anime (requires AniList authentication)',
                      arabic:
                          'جلب مقاطع التخطي للأنمي تلقائيًا (يتطلب تسجيل الدخول إلى AniList)',
                    ),
                    trailing: Switch(
                      value: settingsRepo.isAnimeSkipIntegrationEnabled(),
                      onChanged: (val) {
                        settingsRepo.setAnimeSkipIntegrationEnabled(val);
                        // Trigger a rebuild
                        ref.invalidate(settingsRepositoryProvider);
                      },
                    ),
                    onTap: () {
                      final current = settingsRepo
                          .isAnimeSkipIntegrationEnabled();
                      settingsRepo.setAnimeSkipIntegrationEnabled(!current);
                      ref.invalidate(settingsRepositoryProvider);
                    },
                  ),
                  SettingsTile(
                    icon: Icons.fast_forward_rounded,
                    title: 'IntroDB',
                    isBeta: true,
                    subtitle: appText(
                      context,
                      english: 'Automatically fetch skip segments for TV Shows',
                      arabic: 'جلب مقاطع التخطي للمسلسلات تلقائيًا',
                    ),
                    isLast: true,
                    trailing: Switch(
                      value: settingsRepo.isIntroDbIntegrationEnabled(),
                      onChanged: (val) {
                        settingsRepo.setIntroDbIntegrationEnabled(val);
                        ref.invalidate(settingsRepositoryProvider);
                      },
                    ),
                    onTap: () {
                      final current = settingsRepo
                          .isIntroDbIntegrationEnabled();
                      settingsRepo.setIntroDbIntegrationEnabled(!current);
                      ref.invalidate(settingsRepositoryProvider);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
