import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_providers.dart';
import '../account/animewitcher_account_config.dart';
import '../account/animewitcher_account_service.dart';
import '../storage/settings_repository.dart';
import '../../features/settings/presentation/general_settings_provider.dart';

const MethodChannel _notificationChannel = MethodChannel(
  'dev.akash.skystream/notifications',
);

FirebaseOptions? _animeWitcherMessagingOptions() {
  if (!AnimeWitcherAccountConfig.messagingConfigured) return null;
  final appId = Platform.isIOS
      ? AnimeWitcherAccountConfig.iosAppId
      : AnimeWitcherAccountConfig.androidAppId;
  return FirebaseOptions(
    apiKey: AnimeWitcherAccountConfig.apiKey,
    appId: appId,
    messagingSenderId: AnimeWitcherAccountConfig.messagingSenderId,
    projectId: AnimeWitcherAccountConfig.projectId,
  );
}

Future<bool> prepareAnimeWitcherFirebaseMessaging() async {
  if (!(Platform.isAndroid || Platform.isIOS)) return false;
  final options = _animeWitcherMessagingOptions();
  if (options == null) return false;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }
    FirebaseMessaging.onBackgroundMessage(
      animeWitcherFirebaseMessagingBackgroundHandler,
    );
    return true;
  } catch (error) {
    if (kDebugMode) {
      debugPrint('[Push] Firebase Messaging initialization deferred: $error');
    }
    return false;
  }
}

@pragma('vm:entry-point')
Future<void> animeWitcherFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  final options = _animeWitcherMessagingOptions();
  if (options == null) return;
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: options);
  }
}

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  final service = PushNotificationService(
    accountService: ref.watch(animeWitcherAccountServiceProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

class PushNotificationService {
  PushNotificationService({
    required AnimeWitcherAccountService accountService,
    required SettingsRepository settingsRepository,
  }) : _accountService = accountService,
       _settingsRepository = settingsRepository;

  final AnimeWitcherAccountService _accountService;
  final SettingsRepository _settingsRepository;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  bool _initialized = false;

  bool get messagingConfigured =>
      AnimeWitcherAccountConfig.messagingConfigured && Firebase.apps.isNotEmpty;

  Future<void> initialize() async {
    if (_initialized || !(Platform.isAndroid || Platform.isIOS)) return;
    _initialized = true;

    try {
      await _notificationChannel.invokeMethod<bool>('ensureChannel');
    } catch (_) {}

    if (messagingConfigured) {
      if (Platform.isIOS) {
        await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
        (token) => unawaited(_handleTokenRefresh(token)),
        onError: (Object error) {
          if (kDebugMode) debugPrint('[Push] Token refresh failed: $error');
        },
      );
      _foregroundSubscription = FirebaseMessaging.onMessage.listen(
        (message) => unawaited(_handleForegroundMessage(message)),
      );
    }

    unawaited(syncCurrentRegistration());
  }

  EpisodeNotificationPreference get currentPreference =>
      EpisodeNotificationPreference.fromStorageValue(
        _settingsRepository.getEpisodeNotificationPreference(),
      );

  Future<void> applyPreference(
    EpisodeNotificationPreference preference,
  ) async {
    if (preference == EpisodeNotificationPreference.off) {
      if (messagingConfigured) {
        try {
          await FirebaseMessaging.instance.deleteToken();
        } catch (_) {}
      }
      await _accountService.updateNotificationRegistration(
        fcmToken: '',
        notificationScope: preference.storageValue,
      );
      return;
    }

    final granted = await requestPermission();
    final token = granted ? await _currentFcmToken() : null;
    await _accountService.updateNotificationRegistration(
      fcmToken: token,
      notificationScope: preference.storageValue,
    );
  }

  Future<void> syncCurrentRegistration() async {
    final preference = currentPreference;
    if (preference == EpisodeNotificationPreference.off) {
      await _accountService.updateNotificationRegistration(
        fcmToken: '',
        notificationScope: preference.storageValue,
      );
      return;
    }

    final granted = await requestPermission();
    final token = granted ? await _currentFcmToken() : null;
    await _accountService.updateNotificationRegistration(
      fcmToken: token,
      notificationScope: preference.storageValue,
    );
  }

  Future<bool> requestPermission() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return false;
    bool nativeGranted = false;
    try {
      nativeGranted =
          await _notificationChannel.invokeMethod<bool>('requestPermission') ??
          false;
    } catch (error) {
      if (kDebugMode) debugPrint('[Push] Native permission request failed: $error');
    }
    if (!nativeGranted) return false;

    if (messagingConfigured) {
      try {
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        return settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
      } catch (error) {
        if (kDebugMode) debugPrint('[Push] FCM permission check failed: $error');
      }
    }
    return nativeGranted;
  }

  Future<bool> scheduleTestNotification({
    Duration delay = const Duration(seconds: 15),
  }) async {
    final granted = await requestPermission();
    if (!granted) return false;
    try {
      return await _notificationChannel.invokeMethod<bool>(
            'scheduleTestNotification',
            <String, Object>{
              'delaySeconds': delay.inSeconds,
              'title': 'AnimeWitcher',
              'body': 'اختبار الإشعارات نجح — التطبيق لا يحتاج أن يبقى مفتوحًا.',
            },
          ) ??
          false;
    } catch (error) {
      if (kDebugMode) debugPrint('[Push] Test notification failed: $error');
      return false;
    }
  }

  Future<String?> _currentFcmToken() async {
    if (!messagingConfigured) return null;
    try {
      if (Platform.isIOS) {
        // Recent Firebase iOS SDKs require the APNs token to exist before FCM
        // token APIs are called. Give registration a short window to finish.
        for (var attempt = 0; attempt < 20; attempt++) {
          final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
          if (apnsToken != null && apnsToken.isNotEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken == null || apnsToken.isEmpty) return null;
      }
      return FirebaseMessaging.instance.getToken();
    } catch (error) {
      if (kDebugMode) debugPrint('[Push] Could not get FCM token: $error');
      return null;
    }
  }

  Future<void> _handleTokenRefresh(String token) async {
    final preference = currentPreference;
    if (preference == EpisodeNotificationPreference.off) return;
    await _accountService.updateNotificationRegistration(
      fcmToken: token,
      notificationScope: preference.storageValue,
    );
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    // iOS uses setForegroundNotificationPresentationOptions above. Android
    // needs an explicit local notification while the app is foregrounded.
    if (!Platform.isAndroid) return;
    final title = message.notification?.title ?? message.data['title'];
    final body = message.notification?.body ?? message.data['body'];
    if (title == null && body == null) return;
    try {
      await _notificationChannel.invokeMethod<bool>(
        'showNotification',
        <String, Object>{
          'title': title?.toString() ?? 'AnimeWitcher',
          'body': body?.toString() ?? '',
        },
      );
    } catch (_) {}
  }

  void dispose() {
    unawaited(_tokenRefreshSubscription?.cancel());
    unawaited(_foregroundSubscription?.cancel());
  }
}
