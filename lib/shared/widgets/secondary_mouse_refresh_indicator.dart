import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A [RefreshIndicator] that also supports a desktop-style secondary-mouse
/// pull gesture. Starting at the top of the scrollable, hold the right mouse
/// button and drag downward to refresh.
class SecondaryMouseRefreshIndicator extends StatefulWidget {
  const SecondaryMouseRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final RefreshCallback onRefresh;
  final Widget child;

  @override
  State<SecondaryMouseRefreshIndicator> createState() =>
      _SecondaryMouseRefreshIndicatorState();
}

class _SecondaryMouseRefreshIndicatorState
    extends State<SecondaryMouseRefreshIndicator> {
  static const double _triggerDistance = 72;

  final GlobalKey<RefreshIndicatorState> _indicatorKey =
      GlobalKey<RefreshIndicatorState>();
  int? _secondaryPointer;
  Offset? _dragStart;
  bool _isAtTop = true;
  bool _isRefreshing = false;

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth == 0 &&
        notification.metrics.axis == Axis.vertical) {
      _isAtTop = notification.metrics.extentBefore <= 0.5;
    }
    return false;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons & kSecondaryMouseButton == 0 ||
        !_isAtTop ||
        _isRefreshing) {
      return;
    }
    _secondaryPointer = event.pointer;
    _dragStart = event.position;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_secondaryPointer != event.pointer || _dragStart == null) return;
    if (event.buttons & kSecondaryMouseButton == 0) {
      _resetGesture(event.pointer);
      return;
    }

    final delta = event.position - _dragStart!;
    if (delta.dy >= _triggerDistance && delta.dy > delta.dx.abs()) {
      _secondaryPointer = null;
      _dragStart = null;
      _showRefreshIndicator();
    }
  }

  void _showRefreshIndicator() {
    if (_isRefreshing) return;
    final refresh = _indicatorKey.currentState?.show(atTop: true);
    if (refresh == null) return;
    _isRefreshing = true;
    refresh.whenComplete(() {
      if (mounted) _isRefreshing = false;
    });
  }

  void _resetGesture(int pointer) {
    if (_secondaryPointer != pointer) return;
    _secondaryPointer = null;
    _dragStart = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: (event) => _resetGesture(event.pointer),
      onPointerCancel: (event) => _resetGesture(event.pointer),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: RefreshIndicator(
          key: _indicatorKey,
          onRefresh: widget.onRefresh,
          child: widget.child,
        ),
      ),
    );
  }
}
