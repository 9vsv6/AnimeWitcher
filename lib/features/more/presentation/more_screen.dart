import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/account/account_providers.dart';
import '../../../core/account/animewitcher_account_models.dart';
import '../../characters/presentation/characters_screen.dart';
import '../../settings/presentation/account_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import 'broadcast_schedule_screen.dart';
import 'coming_soon_screen.dart';
import 'global_statistics_screen.dart';
import 'recent_watched_screen.dart';
import 'seasons_screen.dart';
import '../../../core/utils/localized_text.dart';
import '../../../core/utils/layout_constants.dart';
import 'more_sidebar_shell.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  /// One sidebar row per settings group, drawn from the settings screen
  /// itself so the two cannot list different things.
  List<MoreDestination> _settingsDestinations(
    BuildContext context,
    WidgetRef ref,
  ) {
    const icons = <IconData>[
      Icons.tune_rounded,
      Icons.play_circle_outline_rounded,
      Icons.download_rounded,
      Icons.image_outlined,
      Icons.storage_rounded,
      Icons.info_outline_rounded,
    ];

    final groups = const SettingsScreen()
        .settingsSections(context, ref)
        .whereType<SettingsGroup>()
        .toList(growable: false);

    return <MoreDestination>[
      for (var i = 0; i < groups.length; i++)
        MoreDestination(
          icon: i < icons.length ? icons[i] : Icons.settings_rounded,
          label: groups[i].title,
          builder: (_) => _SettingsGroupPane(index: i),
        ),
    ];
  }

  bool _isArabic(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isArabic = _isArabic(context);
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 88;
    final accountState = ref.watch(animeWitcherAccountControllerProvider);
    final accountProfile = accountState.asData?.value.profile;
    final accountPhotoUrl = accountProfile?.photoUrl?.trim() ?? '';

    // A window with room for two columns keeps the list of destinations on
    // screen beside the one being read, and opens on the account rather than
    // on a page of links to press.
    //
    // A tablet gets the desktop layout in both orientations, upright
    // included: the sidebar takes 272 points, which still leaves a 10-inch
    // tablet's 800 with 528 for the page — the measure a settings pane keeps
    // to on a desktop anyway.
    //
    // Both dimensions are asked for, not the device class. A phone in
    // landscape is wide enough to pass a width test and far too short to
    // read two columns; the shortest side is what separates it from a
    // tablet, whatever platform reports it.
    const twoPaneMinimumWidth = 740.0;
    // Above a 4:3 desktop window's 600: two columns need height as much as
    // width, and a short window is better served by the single list.
    const twoPaneMinimumShortestSide = 640.0;
    final size = MediaQuery.sizeOf(context);
    if (size.width >= twoPaneMinimumWidth &&
        size.shortestSide >= twoPaneMinimumShortestSide) {
      return Scaffold(
        appBar: AppBar(centerTitle: false),
        body: MoreSidebarShell(
          header: MoreSidebarHeader(
            name: accountProfile == null
                ? appText(context, english: 'Sign in', arabic: 'تسجيل الدخول')
                : _accountDisplayName(accountProfile),
            // No address here. This card sits on screen the whole time the
            // More section is open, and the account page is where an address
            // belongs — behind an eye, at that.
            subtitle: accountProfile == null
                ? appText(
                    context,
                    english: 'Sync your lists and progress',
                    arabic: 'مزامنة القوائم والتقدم',
                  )
                : appText(
                    context,
                    english: 'Signed in',
                    arabic: 'مسجّل الدخول',
                  ),
            photoUrl: accountPhotoUrl,
          ),
          groups: <MoreDestinationGroup>[
            MoreDestinationGroup(
              heading: moreHeadingSetup(context),
              items: <MoreDestination>[
                MoreDestination(
                  icon: Icons.person_rounded,
                  label: isArabic
                      ? 'حساب AnimeWitcher'
                      : 'AnimeWitcher account',
                  builder: (_) => const AnimeWitcherAccountScreen(),
                ),
              ],
            ),
            MoreDestinationGroup(
              heading: moreHeadingWatching(context),
              items: <MoreDestination>[
                MoreDestination(
                  icon: Icons.history_rounded,
                  label: isArabic ? 'آخر المشاهدات' : 'Recently watched',
                  builder: (_) => const RecentWatchedScreen(),
                ),
                MoreDestination(
                  icon: Icons.groups_rounded,
                  label: isArabic ? 'الشخصيات' : 'Characters',
                  builder: (_) => const CharactersScreen(),
                ),
              ],
            ),
            MoreDestinationGroup(
              heading: moreHeadingBrowse(context),
              items: <MoreDestination>[
                MoreDestination(
                  icon: Icons.upcoming_rounded,
                  label: isArabic ? 'القادم قريبًا' : 'Coming soon',
                  builder: (_) => const ComingSoonScreen(),
                ),
                MoreDestination(
                  icon: Icons.query_stats_rounded,
                  label: isArabic ? 'الإحصائيات العالمية' : 'Global statistics',
                  builder: (_) => const GlobalStatisticsScreen(),
                ),
                MoreDestination(
                  icon: Icons.calendar_month_rounded,
                  label: isArabic ? 'المواسم' : 'Seasons',
                  builder: (_) => const SeasonsScreen(),
                ),
                MoreDestination(
                  icon: Icons.calendar_view_week_rounded,
                  label: isArabic ? 'جدول البث' : 'Broadcast schedule',
                  builder: (_) => const BroadcastScheduleScreen(),
                ),
              ],
            ),
            // Settings arrive as their own rows rather than as one row that
            // opens a page of six groups: the sidebar is the place a viewer
            // looks for "player" or "downloads", and a list of names is what
            // it is for.
            MoreDestinationGroup(
              heading: moreHeadingApp(context),
              items: _settingsDestinations(context, ref),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      // No title: the window's caption buttons are painted over this same
      // corner, and the two collided. The bar stays for its spacing.
      appBar: AppBar(centerTitle: false),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          _MorePanel(
            children: [
              _MoreTile(
                icon: accountProfile == null
                    ? Icons.account_circle_rounded
                    : Icons.cloud_done_rounded,
                leading: accountPhotoUrl.isEmpty
                    ? null
                    : CircleAvatar(
                        radius: 24,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundImage: NetworkImage(accountPhotoUrl),
                        onForegroundImageError: (_, _) {},
                        child: Icon(
                          Icons.person_rounded,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                title: accountProfile == null
                    ? (isArabic
                          ? 'تسجيل الدخول أو إنشاء حساب'
                          : 'Sign in or create an account')
                    : _accountDisplayName(accountProfile),
                subtitle: accountState.isLoading
                    ? (isArabic
                          ? 'جارٍ التحقق من الحساب...'
                          : 'Checking account...')
                    : accountProfile == null
                    ? (isArabic
                          ? 'مزامنة القوائم والحلقات المشاهدة '
                                'وتقدم التشغيل'
                          : 'Sync lists, watched episodes, and playback progress')
                    : accountProfile.email ??
                          (isArabic
                              ? 'المزامنة مفعلة'
                              : 'Synchronization enabled'),
                trailing: accountState.isLoading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AnimeWitcherAccountScreen(),
                  ),
                ),
              ),
              _MoreTile(
                icon: Icons.history_rounded,
                title: isArabic ? 'آخر المشاهدات' : 'Recently watched',
                subtitle: isArabic
                    ? 'آخر الأنميات والأفلام التي شاهدتها'
                    : 'Anime and movies you watched recently',
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RecentWatchedScreen(),
                  ),
                ),
              ),
              _MoreTile(
                icon: Icons.groups_rounded,
                title: isArabic ? 'الشخصيات' : 'Characters',
                subtitle: isArabic
                    ? 'تصفح الشخصيات وابحث عنها وأدر المفضلة'
                    : 'Browse, search, and favorite characters',
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CharactersScreen(),
                  ),
                ),
              ),
              _MoreTile(
                icon: Icons.upcoming_rounded,
                title: isArabic ? 'القادم قريبًا' : 'Coming soon',
                subtitle: isArabic
                    ? 'أنميات لم يتم بثها بعد حسب بيانات AnimeWitcher'
                    : 'Anime that has not aired yet, from AnimeWitcher',
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ComingSoonScreen(),
                  ),
                ),
              ),
              _MoreTile(
                icon: Icons.query_stats_rounded,
                title: isArabic ? 'الإحصائيات العالمية' : 'Global statistics',
                subtitle: isArabic
                    ? 'إحصائيات المشاهدات والحلقات والأفلام'
                    : 'Global viewing, episode, and movie statistics',
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const GlobalStatisticsScreen(),
                  ),
                ),
              ),
              _MoreTile(
                icon: Icons.calendar_month_rounded,
                title: isArabic ? 'المواسم' : 'Seasons',
                subtitle: isArabic
                    ? 'الموسم السابق والحالي والقادم وجميع المواسم'
                    : 'Previous, current, next, and all seasons',
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SeasonsScreen(),
                  ),
                ),
              ),
              _MoreTile(
                icon: Icons.calendar_view_week_rounded,
                title: isArabic ? 'جدول البث' : 'Broadcast schedule',
                subtitle: isArabic
                    ? 'الأنميات موزعة على أيام الأسبوع السبعة'
                    : 'Anime grouped across the seven weekdays',
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BroadcastScheduleScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MorePanel(
            children: [
              _MoreTile(
                icon: Icons.settings_rounded,
                title: isArabic ? 'الإعدادات' : 'Settings',
                subtitle: isArabic
                    ? 'إعدادات التطبيق والمشغل'
                    : 'App and player settings',
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The name to show for a signed-in account, falling back to the address.
String _accountDisplayName(AnimeWitcherProfile profile) {
  final userName = profile.userName?.trim() ?? '';
  if (userName.isNotEmpty) return userName;
  final email = profile.email?.trim() ?? '';
  return email.isEmpty ? 'AnimeWitcher' : email;
}

/// The destinations, in one panel.
///
/// Eight rounded cards down a phone screen is eight objects to take in before
/// you have read a word. One panel with hairlines between its rows is a list,
/// which is what this is.
class _MorePanel extends StatelessWidget {
  const _MorePanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      // The same neutral grey the settings panels use — mixed from the page,
      // since the amber-seeded surface tokens carry a brown tint.
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colors.onSurface.withValues(alpha: 0.06),
          colors.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.onSurface.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 54,
                  endIndent: 14,
                  color: colors.onSurface.withValues(alpha: 0.1),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// One destination: its glyph, its name, and what it holds.
class _MoreTile extends StatelessWidget {
  final IconData icon;
  final Widget? leading;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _MoreTile({
    required this.icon,
    this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // The glyph on its own, as the settings rows draw theirs: one
              // list style across the app rather than a second one here.
              leading ??
                  SizedBox.square(
                    dimension: 26,
                    child: Icon(icon, size: 22, color: colors.primary),
                  ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing ?? const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsGroupPane extends ConsumerWidget {
  const _SettingsGroupPane({required this.index});

  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = const SettingsScreen()
        .settingsSections(context, ref)
        .whereType<SettingsGroup>()
        .toList(growable: false);
    if (index >= groups.length) return const SizedBox.shrink();

    // Settings rows are a label at one end and its value at the other. Left
    // to fill a 1600-point pane they put the two on opposite sides of the
    // desk, so they keep to the shared reading measure.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: LayoutConstants.contentMaxWidth,
        ),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            8,
            16,
            8,
            MediaQuery.viewPaddingOf(context).bottom + 96,
          ),
          children: [groups[index]],
        ),
      ),
    );
  }
}
