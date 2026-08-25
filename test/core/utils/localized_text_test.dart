import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/utils/localized_text.dart';

void main() {
  testWidgets('appText always returns Arabic', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: SizedBox(),
      ),
    );
    final context = tester.element(find.byType(SizedBox));

    expect(isArabicAppLocale(context), isTrue);
    expect(
      appText(context, english: 'Downloads', arabic: 'التنزيلات'),
      'التنزيلات',
    );
  });
}
