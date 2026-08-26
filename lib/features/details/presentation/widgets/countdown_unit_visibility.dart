/// Which countdown unit cards should render for a remaining duration.
///
/// Zero-value leading units are dropped so the remaining cards can be centered:
/// - hide days when days == 0
/// - hide hours only when days == 0 and hours == 0
/// - hide minutes only when days, hours, and minutes are all 0
/// Seconds stay visible for any positive remaining time.
class CountdownUnitVisibility {
  const CountdownUnitVisibility({
    required this.showDays,
    required this.showHours,
    required this.showMinutes,
    required this.showSeconds,
  });

  final bool showDays;
  final bool showHours;
  final bool showMinutes;
  final bool showSeconds;

  factory CountdownUnitVisibility.fromRemaining(Duration remaining) {
    if (remaining <= Duration.zero) {
      return const CountdownUnitVisibility(
        showDays: false,
        showHours: false,
        showMinutes: false,
        showSeconds: false,
      );
    }

    final days = remaining.inDays;
    final hours = remaining.inHours.remainder(24);
    final minutes = remaining.inMinutes.remainder(60);

    return CountdownUnitVisibility(
      showDays: days > 0,
      showHours: hours > 0 || days > 0,
      showMinutes: minutes > 0 || hours > 0 || days > 0,
      showSeconds: true,
    );
  }

  int get visibleCount =>
      (showDays ? 1 : 0) +
      (showHours ? 1 : 0) +
      (showMinutes ? 1 : 0) +
      (showSeconds ? 1 : 0);
}
