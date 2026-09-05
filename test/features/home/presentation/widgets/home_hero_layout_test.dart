import 'package:animewitcher/core/providers/device_info_provider.dart';
import 'package:animewitcher/features/home/presentation/widgets/home_hero_layout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hero frame follows phone rotation and omits tablet spacing', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> check(Size size, double top, double height) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceProfileProvider.overrideWith(
              (ref) async => const DeviceProfile(),
            ),
          ],
          child: MaterialApp(
            home: MediaQuery(
              // A raw status inset must be used even if padding was modified.
              data: MediaQueryData(
                size: size,
                viewPadding: const EdgeInsets.only(top: 44),
                padding: const EdgeInsets.only(top: 100),
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: HomeHeroFrame(
                  builder: (context, height) => const ColoredBox(
                    key: ValueKey('artwork'),
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final rect = tester.getRect(find.byKey(const ValueKey('artwork')));
      expect(rect.top, top);
      expect(rect.width, size.width);
      expect(rect.height, closeTo(height, 0.01));
    }

    await check(const Size(390, 844), 44, 219.375);
    await check(const Size(844, 390), 0, 280.8);
    await check(const Size(768, 1024), 0, 432);
    await check(const Size(1440, 900), 0, 540);
  });
}
