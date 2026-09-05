import 'package:animewitcher/core/utils/window_controls_inset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The inset is zero away from Windows, where nothing is painted over that
  // corner, so a title is only expected to move where there is something to
  // move out from under.
  final expectedShift = windowControlsTrailingInset;

  testWidgets('a pinned left-to-right header reserves the corner in actions', (
    tester,
  ) async {
    // The shape every screen behind the More list uses: the bar itself is
    // held left-to-right so its slots keep their sides, and the title is
    // aligned to the trailing edge by hand for Arabic.
    Widget header({required bool reserve}) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(kToolbarHeight),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: AppBar(
                automaticallyImplyLeading: false,
                titleSpacing: 16,
                actions: reserve ? const <Widget>[WindowControlsGap()] : null,
                title: const Align(
                  alignment: Alignment.centerRight,
                  child: Text('الإحصائيات العالمية'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(header(reserve: false));
    final bare = tester.getRect(find.text('الإحصائيات العالمية')).right;

    await tester.pumpWidget(header(reserve: true));
    final reserved = tester.getRect(find.text('الإحصائيات العالمية')).right;

    expect(bare - reserved, expectedShift);
  });

  testWidgets('a right-to-left header reserves it in the leading slot', (
    tester,
  ) async {
    // The account screen follows the app's language instead, which swaps the
    // slots: the corner the caption buttons occupy is the leading one there,
    // so reserving it in `actions` would clear the wrong edge.
    Widget header({required bool reserve}) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leadingWidth: reserve ? windowControlsTrailingInset : null,
            leading: reserve ? const SizedBox.shrink() : null,
            title: const Text('حساب AnimeWitcher'),
          ),
        ),
      ),
    );

    await tester.pumpWidget(header(reserve: false));
    final bare = tester.getRect(find.text('حساب AnimeWitcher')).right;

    await tester.pumpWidget(header(reserve: true));
    final reserved = tester.getRect(find.text('حساب AnimeWitcher')).right;

    expect(bare - reserved, expectedShift);
  });
}
