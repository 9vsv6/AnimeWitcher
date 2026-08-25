import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animewitcher/core/providers/device_info_provider.dart';
import 'package:animewitcher/core/services/notification_service.dart';

/// Exact Material 3 Expressive animation curves & timings.
class ToastCurves {
  /// Main entrance pop-in curve: cubic-bezier(0.38, 1.21, 0.22, 1.00)
  static const Curve expressiveDefaultSpatial = Cubic(0.38, 1.21, 0.22, 1.00);

  /// Fast snappy bounce for small icons/badges: cubic-bezier(0.42, 1.67, 0.21, 0.90)
  static const Curve expressiveFastSpatial = Cubic(0.42, 1.67, 0.21, 0.90);

  /// Exit / Dismiss curve: cubic-bezier(0.05, 0.70, 0.10, 1.00)
  static const Curve emphasizedDecel = Cubic(0.05, 0.70, 0.10, 1.00);
}

/// Global floating pill toasts — same look as “watch history cleared”.
class M3ToastOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const M3ToastOverlay({super.key, required this.child});

  @override
  ConsumerState<M3ToastOverlay> createState() => _M3ToastOverlayState();
}

class _M3ToastOverlayState extends ConsumerState<M3ToastOverlay> {
  @override
  Widget build(BuildContext context) {
    final notificationService = ref.watch(notificationServiceProvider);
    final profile = ref.watch(deviceProfileProvider).asData?.value;
    final isDesktopOrTv =
        (profile?.isDesktopOS ?? false) ||
        (profile?.isTv ?? false) ||
        MediaQuery.sizeOf(context).width >= 720;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: ListenableBuilder(
            listenable: notificationService,
            builder: (context, _) {
              final toasts = notificationService.toasts;
              if (toasts.isEmpty) {
                return const SizedBox.shrink();
              }

              return IgnorePointer(
                ignoring: false,
                child: SafeArea(
                  child: Align(
                    alignment: isDesktopOrTv
                        ? Alignment.bottomRight
                        : Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: isDesktopOrTv ? 24 : 16,
                        right: isDesktopOrTv ? 24 : 16,
                        bottom: isDesktopOrTv ? 24 : 16,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 360,
                          minWidth: 160,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: isDesktopOrTv
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.center,
                          children: [
                            for (int i = 0; i < toasts.length; i++) ...[
                              if (i > 0) const SizedBox(height: 10),
                              _M3ToastCard(
                                key: ValueKey(toasts[i].id),
                                item: toasts[i],
                                onDismiss: () => notificationService
                                    .dismissToast(toasts[i].id),
                                onHoverStart: () => notificationService
                                    .pauseTimer(toasts[i].id),
                                onHoverEnd: () => notificationService
                                    .resumeTimer(toasts[i].id),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _M3ToastCard extends StatefulWidget {
  final ToastItem item;
  final VoidCallback onDismiss;
  final VoidCallback onHoverStart;
  final VoidCallback onHoverEnd;

  const _M3ToastCard({
    super.key,
    required this.item,
    required this.onDismiss,
    required this.onHoverStart,
    required this.onHoverEnd,
  });

  @override
  State<_M3ToastCard> createState() => _M3ToastCardState();
}

class _M3ToastCardState extends State<_M3ToastCard>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _iconBounceController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _iconScaleAnimation;

  bool _isExiting = false;

  static const double _pillRadius = 999;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _iconBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: ToastCurves.expressiveDefaultSpatial,
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: ToastCurves.expressiveDefaultSpatial,
          ),
        );

    _iconScaleAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _iconBounceController,
        curve: ToastCurves.expressiveFastSpatial,
      ),
    );

    _entranceController.forward();
    _iconBounceController.forward();
  }

  Future<void> _handleDismiss() async {
    if (_isExiting) return;
    _isExiting = true;

    _entranceController.duration = const Duration(milliseconds: 220);
    await _entranceController.reverse();
    if (mounted) {
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _iconBounceController.dispose();
    super.dispose();
  }

  Color _badgeColor(ThemeData theme) {
    switch (widget.item.type) {
      case ToastType.success:
        return const Color(0xFF81C784);
      case ToastType.error:
        return const Color(0xFFEF5350);
      case ToastType.info:
        return theme.colorScheme.primary;
    }
  }

  IconData _badgeIcon() {
    if (widget.item.icon != null) return widget.item.icon!;
    switch (widget.item.type) {
      case ToastType.success:
        return Icons.check_rounded;
      case ToastType.error:
        return Icons.close_rounded;
      case ToastType.info:
        return Icons.info_rounded;
    }
  }

  Widget _buildStatusBadge(ThemeData theme) {
    if (widget.item.leading != null) return widget.item.leading!;

    final badgeColor = _badgeColor(theme);
    final onBadge = widget.item.type == ToastType.error
        ? Colors.white
        : const Color(0xFF1B1B1F);

    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: badgeColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: badgeColor.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(_badgeIcon(), size: 17, color: onBadge),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final surfaceColor = isDark
        ? const Color(0xE61C1C1E)
        : theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.92);

    final borderColor = isDark
        ? const Color(0x33FFFFFF)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.40);

    final textColor = isDark
        ? const Color(0xFFF5F5F7)
        : theme.colorScheme.onSurface;

    final subtitleColor = isDark
        ? const Color(0xFFCAC4D0)
        : theme.colorScheme.onSurfaceVariant;

    return MouseRegion(
      onEnter: (_) => widget.onHoverStart(),
      onExit: (_) => widget.onHoverEnd(),
      child: SlideTransition(
        position: _slideAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: FadeTransition(
            opacity: _opacityAnimation,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _handleDismiss,
                borderRadius: BorderRadius.circular(_pillRadius),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_pillRadius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.40 : 0.15,
                        ),
                        blurRadius: 18,
                        spreadRadius: 0,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_pillRadius),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 160,
                          maxWidth: 360,
                        ),
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          borderRadius: BorderRadius.circular(_pillRadius),
                          border: Border.all(color: borderColor, width: 1),
                          gradient: isDark
                              ? const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x22FFFFFF),
                                    Color(0x00000000),
                                  ],
                                  stops: [0.0, 0.35],
                                )
                              : null,
                        ),
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          10,
                          10,
                          16,
                          10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            ScaleTransition(
                              scale: _iconScaleAnimation,
                              child: _buildStatusBadge(theme),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (widget.item.title != null &&
                                      widget.item.title!.isNotEmpty) ...[
                                    Text(
                                      widget.item.title!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        height: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.item.message,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: subtitleColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                        height: 1.2,
                                      ),
                                    ),
                                  ] else ...[
                                    Text(
                                      widget.item.message,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        height: 1.25,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (widget.item.actionLabel != null &&
                                widget.item.onAction != null) ...[
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () {
                                  widget.item.onAction!();
                                  _handleDismiss();
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  foregroundColor: _badgeColor(theme),
                                ),
                                child: Text(
                                  widget.item.actionLabel!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
