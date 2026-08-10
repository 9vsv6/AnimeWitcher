import 'package:flutter/material.dart';
import 'package:skystream/shared/widgets/taskbar_visibility.dart';

import '../../settings/presentation/settings_screen.dart';
import 'broadcast_schedule_screen.dart';
import 'seasons_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  bool _isArabic(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';

  @override
  Widget build(BuildContext context) {
    final isArabic = _isArabic(context);
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 88;

    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'المزيد' : 'More'),
        centerTitle: false,
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        child: Column(
          children: [
            _MoreTile(
              icon: Icons.calendar_month_rounded,
              title: isArabic ? 'المواسم' : 'Seasons',
              subtitle: isArabic
                  ? 'الموسم السابق والحالي والقادم وجميع المواسم'
                  : 'Previous, current, next, and all seasons',
              onTap: () => pushWithTaskbarHidden<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const SeasonsScreen(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _MoreTile(
              icon: Icons.calendar_view_week_rounded,
              title: isArabic ? 'جدول البث' : 'Broadcast schedule',
              subtitle: isArabic
                  ? 'الأنميات موزعة على أيام الأسبوع السبعة'
                  : 'Anime grouped across the seven weekdays',
              onTap: () => pushWithTaskbarHidden<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const BroadcastScheduleScreen(),
                ),
              ),
            ),
            const Spacer(),
            Divider(color: theme.dividerColor.withValues(alpha: 0.55)),
            const SizedBox(height: 8),
            _MoreTile(
              icon: Icons.settings_rounded,
              title: isArabic ? 'الإعدادات' : 'Settings',
              subtitle: isArabic
                  ? 'إعدادات التطبيق والحساب والمشغل'
                  : 'App, account, and player settings',
              onTap: () => pushWithTaskbarHidden<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: colors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
