from pathlib import Path

path = Path('test/core/services/download_unknown_size_recovery_test.dart')
text = path.read_text()

old = """          if (slowFirstBody && start == 0 && end == 9) {
            request.response.add(<int>[0, 1, 2, 3]);
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 250));
            request.response.add(<int>[4, 5, 6, 7, 8, 9]);
          } else {
"""
new = """          if (slowFirstBody && end == 9) {
            final firstEnd = (start + 1).clamp(start, end);
            request.response.add(
              List<int>.generate(firstEnd - start + 1, (i) => start + i),
            );
            await request.response.flush();
            await Future<void>.delayed(const Duration(seconds: 1));
            if (firstEnd < end) {
              request.response.add(
                List<int>.generate(end - firstEnd, (i) => firstEnd + 1 + i),
              );
            }
          } else {
"""
if text.count(old) != 1:
    raise SystemExit(f'slow response anchor count={text.count(old)}')
text = text.replace(old, new, 1)

old = """    slowFirstBody = true;
    final first = DownloadRangeTransfer(dio);
    final paused = Completer<int>();
    expect(
      await first.start(
        id: 'episode',
        url: url,
        headers: const {},
        file: file,
        existingBytes: 0,
        expectedBytes: -1,
"""
new = """    // Simulate bytes left by a killed process, then interrupt the resumed
    // unknown-size stream again before launching a fresh service instance.
    await file.writeAsBytes(<int>[0, 1, 2]);
    slowFirstBody = true;
    final first = DownloadRangeTransfer(dio);
    final paused = Completer<int>();
    expect(
      await first.start(
        id: 'episode',
        url: url,
        headers: const {},
        file: file,
        existingBytes: 3,
        expectedBytes: -1,
"""
if text.count(old) != 1:
    raise SystemExit(f'unknown size test start anchor count={text.count(old)}')
text = text.replace(old, new, 1)

text = text.replace(
    "for (var i = 0; i < 100 && await file.length() < 4; i++) {",
    "for (var i = 0; i < 100 && await file.length() < 5; i++) {",
    1,
)
text = text.replace(
    "expect(durable, greaterThanOrEqualTo(4));",
    "expect(durable, greaterThanOrEqualTo(5));",
    1,
)

path.write_text(text)
print('Stabilized unknown-size interruption/relaunch regression test.')
