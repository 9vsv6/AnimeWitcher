import 'package:flutter_test/flutter_test.dart';
import 'package:animewitcher/features/details/presentation/widgets/countdown_unit_visibility.dart';

void main() {
  group('CountdownUnitVisibility.fromRemaining', () {
    test('hides days when remaining is under one day', () {
      final visibility = CountdownUnitVisibility.fromRemaining(
        const Duration(hours: 22, minutes: 39, seconds: 22),
      );

      expect(visibility.showDays, isFalse);
      expect(visibility.showHours, isTrue);
      expect(visibility.showMinutes, isTrue);
      expect(visibility.showSeconds, isTrue);
      expect(visibility.visibleCount, 3);
    });

    test('keeps hours when days remain even if hours are 0', () {
      final visibility = CountdownUnitVisibility.fromRemaining(
        const Duration(days: 2, minutes: 15),
      );

      expect(visibility.showDays, isTrue);
      expect(visibility.showHours, isTrue);
      expect(visibility.showMinutes, isTrue);
      expect(visibility.showSeconds, isTrue);
      expect(visibility.visibleCount, 4);
    });

    test('hides hours only when days and hours are both 0', () {
      final visibility = CountdownUnitVisibility.fromRemaining(
        const Duration(minutes: 12, seconds: 5),
      );

      expect(visibility.showDays, isFalse);
      expect(visibility.showHours, isFalse);
      expect(visibility.showMinutes, isTrue);
      expect(visibility.showSeconds, isTrue);
      expect(visibility.visibleCount, 2);
    });

    test('hides minutes only when days, hours, and minutes are 0', () {
      final visibility = CountdownUnitVisibility.fromRemaining(
        const Duration(seconds: 22),
      );

      expect(visibility.showDays, isFalse);
      expect(visibility.showHours, isFalse);
      expect(visibility.showMinutes, isFalse);
      expect(visibility.showSeconds, isTrue);
      expect(visibility.visibleCount, 1);
    });

    test('keeps minutes when hours remain even if minutes are 0', () {
      final visibility = CountdownUnitVisibility.fromRemaining(
        const Duration(hours: 3),
      );

      expect(visibility.showDays, isFalse);
      expect(visibility.showHours, isTrue);
      expect(visibility.showMinutes, isTrue);
      expect(visibility.showSeconds, isTrue);
    });

    test('hides every unit when remaining is zero', () {
      final visibility = CountdownUnitVisibility.fromRemaining(Duration.zero);

      expect(visibility.showDays, isFalse);
      expect(visibility.showHours, isFalse);
      expect(visibility.showMinutes, isFalse);
      expect(visibility.showSeconds, isFalse);
      expect(visibility.visibleCount, 0);
    });
  });
}
