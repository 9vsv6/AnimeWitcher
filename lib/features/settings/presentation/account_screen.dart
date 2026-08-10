import 'package:flutter/material.dart';
import 'package:skystream/shared/widgets/apple_liquid_glass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/account/account_providers.dart';
import '../../../core/account/animewitcher_account_config.dart';
import '../../../core/account/animewitcher_account_models.dart';
import '../../../core/utils/localized_text.dart';
import '../../../core/utils/layout_constants.dart';
import '../../../shared/widgets/custom_widgets.dart';
import 'widgets/settings_widgets.dart';

enum _AccountFormMode { signIn, createAccount }

class AnimeWitcherAccountScreen extends ConsumerStatefulWidget {
  const AnimeWitcherAccountScreen({super.key});

  @override
  ConsumerState<AnimeWitcherAccountScreen> createState() =>
      _AnimeWitcherAccountScreenState();
}

class _AnimeWitcherAccountScreenState
    extends ConsumerState<AnimeWitcherAccountScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  _AccountFormMode _mode = _AccountFormMode.signIn;
  bool _submitting = false;

  bool get _isArabic =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(animeWitcherAccountControllerProvider);
    final snapshot = account.asData?.value;
    final profile = snapshot?.profile;
    final configured = AnimeWitcherAccountConfig.firebaseConfigured;
    final busy = _submitting || account.isLoading || !configured;
    final asyncError = account.when<Object?>(
      data: (_) => null,
      error: (error, _) => error,
      loading: () => null,
    );

    return Scaffold(
      appBar: AppBar(
        leading: !appleUsesPersistentLiquidGlassHeader &&
                Navigator.of(context).canPop()
            ? const AppleLiquidGlassBackButton()
            : null,
        title: ApplePersistentGlassHeaderScope(
          enabled: Navigator.of(context).canPop(),
          onBack: () => Navigator.of(context).maybePop(),
          child: Text(
            appText(
              context,
              english: 'AnimeWitcher account',
              arabic: 'حساب AnimeWitcher',
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              const SizedBox(height: LayoutConstants.spacingMd),
              if (profile != null)
                _buildSignedIn(profile, snapshot!, busy)
              else
                _buildSignedOut(busy, asyncError),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignedOut(bool busy, Object? asyncError) {
    final colors = Theme.of(context).colorScheme;
    final isCreate = _mode == _AccountFormMode.createAccount;
    return Column(
      children: [
        if (!AnimeWitcherAccountConfig.firebaseConfigured)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LayoutConstants.spacingLg,
              LayoutConstants.spacingMd,
              LayoutConstants.spacingLg,
              0,
            ),
            child: _ErrorBanner(
              message: appText(
                context,
                english:
                    'Account sync is not configured in this build. Add the AnimeWitcher Firebase values through build secrets.',
                arabic:
                    'مزامنة الحساب غير مهيأة في هذه النسخة. أضف إعدادات Firebase الخاصة بـ AnimeWitcher من أسرار البناء.',
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LayoutConstants.spacingLg,
            vertical: LayoutConstants.spacingMd,
          ),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_sync_rounded,
                  size: 36,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: LayoutConstants.spacingMd),
              Text(
                appText(
                  context,
                  english: 'Keep your anime progress with you',
                  arabic: 'خلي تقدمك وقوائمك معك دائمًا',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: LayoutConstants.spacingSm),
              Text(
                appText(
                  context,
                  english:
                      'Sync watched episodes, resume positions, and all AnimeWitcher lists across devices.',
                  arabic:
                      'زامن الحلقات المشاهدة ومكان إكمال الحلقة وكل قوائم AnimeWitcher بين أجهزتك.',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SettingsGroup(
          title: appText(
            context,
            english: isCreate ? 'Create a new account' : 'Sign in',
            arabic: isCreate ? 'إنشاء حساب جديد' : 'تسجيل الدخول',
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(LayoutConstants.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<_AccountFormMode>(
                    segments: [
                      ButtonSegment<_AccountFormMode>(
                        value: _AccountFormMode.signIn,
                        icon: const Icon(Icons.login_rounded),
                        label: Text(
                          appText(
                            context,
                            english: 'Sign in',
                            arabic: 'دخول',
                          ),
                        ),
                      ),
                      ButtonSegment<_AccountFormMode>(
                        value: _AccountFormMode.createAccount,
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: Text(
                          appText(
                            context,
                            english: 'New account',
                            arabic: 'حساب جديد',
                          ),
                        ),
                      ),
                    ],
                    selected: <_AccountFormMode>{_mode},
                    onSelectionChanged: busy
                        ? null
                        : (selection) {
                            setState(() => _mode = selection.first);
                          },
                  ),
                  const SizedBox(height: LayoutConstants.spacingLg),
                  if (isCreate) ...[
                    CustomTextField(
                      controller: _nameController,
                      hintText: appText(
                        context,
                        english: 'User name',
                        arabic: 'اسم المستخدم',
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: LayoutConstants.spacingMd),
                  ],
                  CustomTextField(
                    controller: _emailController,
                    hintText: appText(
                      context,
                      english: 'Email address',
                      arabic: 'البريد الإلكتروني',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: LayoutConstants.spacingMd),
                  CustomTextField(
                    controller: _passwordController,
                    hintText: appText(
                      context,
                      english: 'Password',
                      arabic: 'كلمة المرور',
                    ),
                    obscureText: true,
                    textInputAction: isCreate
                        ? TextInputAction.next
                        : TextInputAction.done,
                    onSubmitted: (_) {
                      if (!isCreate && !busy) _submitEmail();
                    },
                  ),
                  if (isCreate) ...[
                    const SizedBox(height: LayoutConstants.spacingMd),
                    CustomTextField(
                      controller: _confirmController,
                      hintText: appText(
                        context,
                        english: 'Confirm password',
                        arabic: 'تأكيد كلمة المرور',
                      ),
                      obscureText: true,
                      onSubmitted: (_) {
                        if (!busy) _submitEmail();
                      },
                    ),
                  ],
                  if (asyncError != null) ...[
                    const SizedBox(height: LayoutConstants.spacingMd),
                    _ErrorBanner(message: _localizedError(asyncError)),
                  ],
                  const SizedBox(height: LayoutConstants.spacingLg),
                  FilledButton.icon(
                    onPressed: busy ? null : _submitEmail,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isCreate
                                ? Icons.person_add_alt_1_rounded
                                : Icons.login_rounded,
                          ),
                    label: Text(
                      appText(
                        context,
                        english: isCreate ? 'Create account' : 'Sign in',
                        arabic: isCreate ? 'إنشاء الحساب' : 'تسجيل الدخول',
                      ),
                    ),
                  ),
                  if (!isCreate)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: busy ? null : _showPasswordResetDialog,
                        child: Text(
                          appText(
                            context,
                            english: 'Forgot password?',
                            arabic: 'نسيت كلمة المرور؟',
                          ),
                        ),
                      ),
                    ),
                  if (!isCreate) ...[
                    const SizedBox(height: LayoutConstants.spacingSm),
                    Row(
                      children: [
                        Expanded(child: Divider(color: colors.outlineVariant)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            appText(
                              context,
                              english: 'or',
                              arabic: 'أو',
                            ),
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ),
                        Expanded(child: Divider(color: colors.outlineVariant)),
                      ],
                    ),
                    const SizedBox(height: LayoutConstants.spacingMd),
                    OutlinedButton.icon(
                      onPressed:
                          busy || !AnimeWitcherAccountConfig.googleConfigured
                          ? null
                          : _submitGoogle,
                      icon: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.outline),
                        ),
                        child: const Text(
                          'G',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      label: Text(
                        appText(
                          context,
                          english: 'Continue with Google',
                          arabic: 'المتابعة باستخدام Google',
                        ),
                      ),
                    ),
                    if (!AnimeWitcherAccountConfig.googleConfigured) ...[
                      const SizedBox(height: LayoutConstants.spacingSm),
                      Text(
                        appText(
                          context,
                          english:
                              'Google sign-in needs the iOS OAuth client in this build. Email sign-in is ready.',
                          arabic:
                              'دخول Google يحتاج إعداد OAuth الخاص بـ iOS في نسخة البناء. الدخول بالبريد جاهز.',
                        ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSignedIn(
    AnimeWitcherProfile profile,
    AnimeWitcherAccountSnapshot snapshot,
    bool busy,
  ) {
    final colors = Theme.of(context).colorScheme;
    final photoUrl = profile.photoUrl?.trim() ?? '';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LayoutConstants.spacingLg,
            vertical: LayoutConstants.spacingMd,
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: colors.primaryContainer,
                foregroundImage: photoUrl.isEmpty
                    ? null
                    : NetworkImage(photoUrl),
                child: photoUrl.isEmpty
                    ? Icon(
                        Icons.person_rounded,
                        size: 42,
                        color: colors.onPrimaryContainer,
                      )
                    : null,
              ),
              const SizedBox(height: LayoutConstants.spacingMd),
              Text(
                profile.userName ?? profile.email ?? 'AnimeWitcher',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (profile.email != null) ...[
                const SizedBox(height: 4),
                Text(
                  profile.email!,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        SettingsGroup(
          title: appText(
            context,
            english: 'Account sync',
            arabic: 'مزامنة الحساب',
          ),
          children: [
            SettingsTile(
              icon: Icons.check_circle_rounded,
              title: appText(
                context,
                english: 'Signed in',
                arabic: 'تم تسجيل الدخول',
              ),
              subtitle: profile.signInMethod ==
                      AnimeWitcherSignInMethod.google
                  ? 'Google'
                  : appText(
                      context,
                      english: 'Email and password',
                      arabic: 'البريد وكلمة المرور',
                    ),
              trailing: Icon(
                Icons.cloud_done_rounded,
                color: colors.primary,
              ),
            ),
            SettingsTile(
              icon: Icons.sync_rounded,
              title: appText(
                context,
                english: 'Sync now',
                arabic: 'مزامنة الآن',
              ),
              subtitle: _lastSyncLabel(snapshot.lastSyncAt),
              trailing: busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: busy ? null : _syncNow,
            ),
            SettingsTile(
              icon: Icons.logout_rounded,
              title: appText(
                context,
                english: 'Sign out',
                arabic: 'تسجيل الخروج',
              ),
              subtitle: appText(
                context,
                english: 'Local data will stay on this device',
                arabic: 'ستبقى البيانات المحلية محفوظة على هذا الجهاز',
              ),
              isLast: true,
              onTap: busy ? null : _signOut,
            ),
          ],
        ),
        const SizedBox(height: LayoutConstants.spacingLg),
        SettingsGroup(
          title: appText(
            context,
            english: 'Synchronized data',
            arabic: 'البيانات التي تتم مزامنتها',
          ),
          children: [
            SettingsTile(
              icon: Icons.play_circle_outline_rounded,
              title: appText(
                context,
                english: 'Continue watching',
                arabic: 'إكمال المشاهدة',
              ),
              trailing: const Icon(Icons.check_rounded),
            ),
            SettingsTile(
              icon: Icons.task_alt_rounded,
              title: appText(
                context,
                english: 'Watched episodes',
                arabic: 'الحلقات التي تمت مشاهدتها',
              ),
              trailing: const Icon(Icons.check_rounded),
            ),
            SettingsTile(
              icon: Icons.video_library_rounded,
              title: appText(
                context,
                english: 'Anime lists and favorites',
                arabic: 'قوائم الأنمي والمفضلة',
              ),
              trailing: const Icon(Icons.check_rounded),
              isLast: true,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _submitEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final isCreate = _mode == _AccountFormMode.createAccount;
    if (email.isEmpty || password.isEmpty) {
      _showMessage(
        appText(
          context,
          english: 'Enter your email address and password.',
          arabic: 'أدخل البريد الإلكتروني وكلمة المرور.',
        ),
        isError: true,
      );
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _showMessage(
        appText(
          context,
          english: 'Enter a valid email address.',
          arabic: 'أدخل بريدًا إلكترونيًا صحيحًا.',
        ),
        isError: true,
      );
      return;
    }
    if (isCreate) {
      final userName = _nameController.text.trim();
      if (userName.length < 5 || userName.length > 25) {
        _showMessage(
          appText(
            context,
            english: 'The user name must contain 5 to 25 characters.',
            arabic: 'يجب أن يتكون اسم المستخدم من 5 إلى 25 حرفًا.',
          ),
          isError: true,
        );
        return;
      }
      if (!AnimeWitcherAccountConfig.isTrustedRegistrationEmail(email)) {
        _showMessage(
          appText(
            context,
            english: 'Use a Gmail, Outlook, or Yahoo email address.',
            arabic: 'استخدم بريد Gmail أو Outlook أو Yahoo.',
          ),
          isError: true,
        );
        return;
      }
      if (password.length < 6) {
        _showMessage(
          appText(
            context,
            english: 'The password must contain at least six characters.',
            arabic: 'يجب أن تحتوي كلمة المرور على 6 أحرف على الأقل.',
          ),
          isError: true,
        );
        return;
      }
      if (password != _confirmController.text) {
        _showMessage(
          appText(
            context,
            english: 'The two passwords do not match.',
            arabic: 'كلمتا المرور غير متطابقتين.',
          ),
          isError: true,
        );
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final controller = ref.read(
        animeWitcherAccountControllerProvider.notifier,
      );
      if (isCreate) {
        await controller.createEmailAccount(
          userName: _nameController.text.trim(),
          email: email,
          password: password,
        );
        if (!mounted) return;
        setState(() => _mode = _AccountFormMode.signIn);
        _passwordController.clear();
        _confirmController.clear();
        _showMessage(
          appText(
            context,
            english:
                'Account created. Open the verification link sent to your email, then sign in.',
            arabic:
                'تم إنشاء الحساب. افتح رابط التحقق المرسل إلى بريدك ثم سجل الدخول.',
          ),
        );
      } else {
        await controller.signInWithEmail(email: email, password: password);
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage(_localizedError(error), isError: true);
      if (error is AnimeWitcherAccountException &&
          error.code == 'email-not-verified') {
        _offerVerificationResend(email, password);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitGoogle() async {
    setState(() => _submitting = true);
    try {
      await ref
          .read(animeWitcherAccountControllerProvider.notifier)
          .signInWithGoogle();
    } catch (error) {
      if (mounted) _showMessage(_localizedError(error), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() => _submitting = true);
    try {
      await ref
          .read(animeWitcherAccountControllerProvider.notifier)
          .syncNow();
      if (mounted) {
        _showMessage(
          appText(
            context,
            english: 'Synchronization completed.',
            arabic: 'اكتملت المزامنة.',
          ),
        );
      }
    } catch (error) {
      if (mounted) _showMessage(_localizedError(error), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          appText(
            dialogContext,
            english: 'Sign out?',
            arabic: 'تسجيل الخروج؟',
          ),
        ),
        content: Text(
          appText(
            dialogContext,
            english:
                'Synced data stays in AnimeWitcher and local data stays on this device.',
            arabic:
                'ستبقى البيانات المزامنة في AnimeWitcher والبيانات المحلية على هذا الجهاز.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              appText(dialogContext, english: 'Cancel', arabic: 'إلغاء'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              appText(dialogContext, english: 'Sign out', arabic: 'خروج'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(animeWitcherAccountControllerProvider.notifier)
          .signOut();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showPasswordResetDialog() async {
    final controller = TextEditingController(text: _emailController.text);
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          appText(
            dialogContext,
            english: 'Reset password',
            arabic: 'استعادة كلمة المرور',
          ),
        ),
        content: CustomTextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          hintText: appText(
            dialogContext,
            english: 'Email address',
            arabic: 'البريد الإلكتروني',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              appText(dialogContext, english: 'Cancel', arabic: 'إلغاء'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(
              appText(dialogContext, english: 'Send', arabic: 'إرسال'),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (email == null || email.trim().isEmpty || !mounted) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(animeWitcherAccountControllerProvider.notifier)
          .sendPasswordResetEmail(email.trim());
      if (mounted) {
        _showMessage(
          appText(
            context,
            english: 'Password reset email sent.',
            arabic: 'تم إرسال رابط استعادة كلمة المرور.',
          ),
        );
      }
    } catch (error) {
      if (mounted) _showMessage(_localizedError(error), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _offerVerificationResend(String email, String password) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          appText(
            context,
            english: 'Verify your email before signing in.',
            arabic: 'تحقق من بريدك الإلكتروني قبل تسجيل الدخول.',
          ),
        ),
        action: SnackBarAction(
          label: appText(
            context,
            english: 'Resend',
            arabic: 'إعادة الإرسال',
          ),
          onPressed: () async {
            try {
              await ref
                  .read(animeWitcherAccountControllerProvider.notifier)
                  .resendEmailVerification(email: email, password: password);
              if (mounted) {
                _showMessage(
                  appText(
                    context,
                    english: 'Verification email sent again.',
                    arabic: 'تم إرسال رسالة التحقق مرة ثانية.',
                  ),
                );
              }
            } catch (error) {
              if (mounted) {
                _showMessage(_localizedError(error), isError: true);
              }
            }
          },
        ),
      ),
    );
  }

  String _lastSyncLabel(DateTime? date) {
    if (date == null) {
      return appText(
        context,
        english: 'Not synchronized yet',
        arabic: 'لم تتم المزامنة بعد',
      );
    }
    final local = date.toLocal();
    final value =
        '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return appText(
      context,
      english: 'Last sync: $value',
      arabic: 'آخر مزامنة: $value',
    );
  }

  String _localizedError(Object error) {
    if (error is! AnimeWitcherAccountException) {
      return appText(
        context,
        english: 'The operation could not be completed. Try again.',
        arabic: 'تعذر إكمال العملية. حاول مرة ثانية.',
      );
    }
    final arabic = switch (error.code) {
      'email-already-in-use' => 'يوجد حساب مسجل بهذا البريد.',
      'invalid-credentials' => 'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
      'email-not-verified' => 'لم يتم التحقق من البريد الإلكتروني بعد.',
      'verification-cooldown' =>
        'يمكنك طلب رسالة تفعيل جديدة بعد مرور 60 ثانية.',
      'weak-password' => 'يجب أن تحتوي كلمة المرور على 6 أحرف على الأقل.',
      'untrusted-email-domain' =>
        'استخدم بريد Gmail أو Outlook أو Yahoo.',
      'invalid-email' => 'أدخل بريدًا إلكترونيًا صحيحًا.',
      'user-disabled' => 'تم تعطيل هذا الحساب.',
      'too-many-attempts' => 'محاولات كثيرة. حاول لاحقًا.',
      'google-not-configured' => 'دخول Google غير مهيأ لهذه النسخة.',
      'not-configured' => 'مزامنة AnimeWitcher غير مهيأة لهذه النسخة.',
      'account-banned' => 'تم إيقاف حساب AnimeWitcher هذا.',
      'duplicate-user-documents' =>
        'يوجد تكرار قديم في بيانات الحساب. تواصل مع دعم AnimeWitcher.',
      'permission-denied' => 'رفض خادم AnimeWitcher عملية المزامنة.',
      'invalid-session' => 'انتهت جلسة الحساب. سجل الدخول من جديد.',
      'invalid-user-name' => 'يجب أن يتكون اسم المستخدم من 5 إلى 25 حرفًا.',
      'profile-not-found' => 'لم يتم العثور على ملف حساب AnimeWitcher.',
      'account-not-found' => 'لم يتم العثور على الحساب.',
      'sync-failed' || 'network-or-server-error' =>
        'تعذّر الاتصال بخادم AnimeWitcher. حاول مرة ثانية.',
      _ => error.message,
    };
    return _isArabic ? arabic : error.message;
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? Theme.of(context).colorScheme.error
              : null,
        ),
      );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
