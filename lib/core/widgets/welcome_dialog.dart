import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/presentation/account_screen.dart';
import '../storage/settings_repository.dart';
import '../theme/theme_provider.dart';
import '../utils/layout_constants.dart';
import '../utils/localized_text.dart';

/// Shows the first-launch welcome dialog once per install: a theme picker
/// followed by a sign-in prompt. No-ops on every later launch.
Future<void> maybeShowWelcomeDialog(BuildContext context, WidgetRef ref) async {
  final repository = ref.read(settingsRepositoryProvider);
  if (repository.hasSeenWelcomeDialog()) return;
  await repository.setWelcomeDialogSeen(true);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _WelcomeDialog(),
  );
}

class _WelcomeDialog extends ConsumerStatefulWidget {
  const _WelcomeDialog();

  @override
  ConsumerState<_WelcomeDialog> createState() => _WelcomeDialogState();
}

class _WelcomeDialogState extends ConsumerState<_WelcomeDialog> {
  int _step = 0;

  void _close() => Navigator.of(context).pop();

  void _openSignIn() {
    Navigator.of(context).pop();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => const AnimeWitcherAccountScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: LayoutConstants.spacingLg,
        vertical: LayoutConstants.spacingLg,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LayoutConstants.radiusXxl),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            LayoutConstants.spacingLg,
            LayoutConstants.spacingMd,
            LayoutConstants.spacingLg,
            LayoutConstants.spacingLg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: _close,
                    icon: const Icon(Icons.close_rounded),
                    tooltip: appText(context, english: 'Close', arabic: 'إغلاق'),
                  ),
                ],
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _step == 0
                    ? _ThemeStep(
                        key: const ValueKey('theme'),
                        onContinue: () => setState(() => _step = 1),
                      )
                    : _SignInStep(
                        key: const ValueKey('signIn'),
                        onSignIn: _openSignIn,
                        onSkip: _close,
                      ),
              ),
              const SizedBox(height: LayoutConstants.spacingMd),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _StepDot(active: _step == 0, color: colors.primary),
                  const SizedBox(width: 6),
                  _StepDot(active: _step == 1, color: colors.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.active, required this.color});

  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: active ? 18 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: active ? color : color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(LayoutConstants.radiusPill),
      ),
    );
  }
}

class _ThemeStep extends ConsumerWidget {
  const _ThemeStep({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final currentTheme = ref.watch(appThemeModeProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.13),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.palette_rounded,
            size: 32,
            color: colors.primary,
          ),
        ),
        const SizedBox(height: LayoutConstants.spacingMd),
        Text(
          appText(
            context,
            english: 'Choose your app look',
            arabic: 'اختر مظهر التطبيق',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: LayoutConstants.spacingMd),
        RadioGroup<ThemeMode>(
          groupValue: currentTheme,
          onChanged: (mode) {
            if (mode == null) return;
            ref.read(appThemeModeProvider.notifier).setThemeMode(mode);
          },
          child: Column(
            children: [
              _ThemeOption(
                icon: Icons.brightness_auto_rounded,
                label: appText(context, english: 'System', arabic: 'النظام'),
                value: ThemeMode.system,
                onSelect: () => ref
                    .read(appThemeModeProvider.notifier)
                    .setThemeMode(ThemeMode.system),
              ),
              _ThemeOption(
                icon: Icons.dark_mode_rounded,
                label: appText(context, english: 'Dark', arabic: 'داكن'),
                value: ThemeMode.dark,
                onSelect: () => ref
                    .read(appThemeModeProvider.notifier)
                    .setThemeMode(ThemeMode.dark),
              ),
              _ThemeOption(
                icon: Icons.light_mode_rounded,
                label: appText(context, english: 'Light', arabic: 'فاتح'),
                value: ThemeMode.light,
                onSelect: () => ref
                    .read(appThemeModeProvider.notifier)
                    .setThemeMode(ThemeMode.light),
              ),
            ],
          ),
        ),
        const SizedBox(height: LayoutConstants.spacingSm),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onContinue,
            child: Text(
              appText(context, english: 'Continue', arabic: 'متابعة'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.value,
    required this.onSelect,
  });

  final IconData icon;
  final String label;
  final ThemeMode value;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      trailing: Radio<ThemeMode>(value: value),
      onTap: onSelect,
    );
  }
}

class _SignInStep extends StatelessWidget {
  const _SignInStep({super.key, required this.onSignIn, required this.onSkip});

  final VoidCallback onSignIn;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.13),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.cloud_sync_rounded,
            size: 32,
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
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: LayoutConstants.spacingSm),
        Text(
          appText(
            context,
            english:
                'Sync watched episodes, resume positions, and all AnimeWitcher lists across your devices.',
            arabic:
                'زامن الحلقات المشاهدة ومكان إكمال الحلقة وكل قوائم AnimeWitcher بين أجهزتك.',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: LayoutConstants.spacingLg),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onSignIn,
            icon: const Icon(Icons.login_rounded),
            label: Text(
              appText(context, english: 'Sign in', arabic: 'تسجيل الدخول'),
            ),
          ),
        ),
        const SizedBox(height: LayoutConstants.spacingSm),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: onSkip,
            child: Text(
              appText(context, english: 'Maybe later', arabic: 'لاحقًا'),
            ),
          ),
        ),
      ],
    );
  }
}
