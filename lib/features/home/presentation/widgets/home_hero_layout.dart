import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/device_info_provider.dart';
import '../../../../core/utils/responsive_breakpoints.dart';

/// The artwork and its loading placeholder share one responsive frame.
class HomeHeroFrame extends ConsumerWidget {
  const HomeHeroFrame({super.key, required this.builder});

  final Widget Function(BuildContext context, double height) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final profile = ref.watch(deviceProfileProvider).asData?.value;
    final isWide = profile?.isTv == true ||
        context.isTv ||
        profile?.isLargeScreen == true ||
        context.isTabletOrLarger;
    final isCompactLandscape = context.isHandsetLandscape ||
        (context.isDesktopLandscape && size.height < 560);
    final isPortraitPhone = !isWide &&
        ResponsiveBreakpoints.isHandset(context) &&
        size.height > size.width;
    final topGap = isPortraitPhone ? MediaQuery.viewPaddingOf(context).top : 0.0;
    final height = isWide
        ? size.height * (isCompactLandscape ? 0.72 : 0.60)
        : (isCompactLandscape ? size.height * 0.72 : size.width * 9 / 16);

    return ColoredBox(
      color: Colors.black,
      child: Padding(
        padding: EdgeInsets.only(top: topGap),
        child: SizedBox(
          width: double.infinity,
          height: height,
          child: builder(context, height),
        ),
      ),
    );
  }
}
