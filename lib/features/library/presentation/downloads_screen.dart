import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/device_info_provider.dart';
import '../../../core/utils/layout_constants.dart';
import '../../../core/utils/responsive_breakpoints.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'widgets/downloads_tab.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(deviceProfileProvider).asData?.value;
    final isTv = profile?.isTv == true || context.isTv;
    final isWidescreen = isTv || context.isTabletOrLarger;
    final title = AppLocalizations.of(context)!.downloads;
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
    final titleDirection =
        isArabic ? TextDirection.rtl : TextDirection.ltr;
    final titleAlignment =
        isArabic ? Alignment.centerRight : Alignment.centerLeft;

    final Widget page;
    if (isWidescreen) {
      page = Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                height: LayoutConstants.dashboardHeaderHeight,
                padding: const EdgeInsets.symmetric(
                  horizontal: LayoutConstants.dashboardContentPadding,
                ),
                alignment: titleAlignment,
                child: Directionality(
                  textDirection: titleDirection,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const Expanded(child: DownloadsTab()),
          ],
        ),
      );
    } else {
      page = Scaffold(
        appBar: AppBar(
          centerTitle: false,
          titleSpacing: 16,
          title: Align(
            alignment: titleAlignment,
            child: Directionality(
              textDirection: titleDirection,
              child: Text(title),
            ),
          ),
        ),
        body: const DownloadsTab(),
      );
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: page,
    );
  }
}
