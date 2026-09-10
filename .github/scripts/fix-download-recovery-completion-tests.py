from pathlib import Path
import re

path = Path('test/core/services/download_unknown_size_recovery_test.dart')
text = path.read_text()

pattern = r"  test\('process-style stop keeps bytes and a new runner safely resumes them', \(\) async \{.*?\n  \}\);\n"
replacement = r'''  test('process-style relaunch resumes only exact durable unknown-size bytes', () async {
    // Process death has no orderly callback to await. The only trustworthy
    // evidence after relaunch is the exact file length left on disk.
    await file.writeAsBytes(<int>[0, 1, 2, 3, 4]);
    final relaunched = DownloadRangeTransfer(dio);
    final complete = Completer<(int, int)>();

    expect(
      await relaunched.start(
        id: 'episode',
        url: url,
        headers: const {},
        file: file,
        existingBytes: 5,
        expectedBytes: -1,
        onState: (written, total, done) async {
          if (done && !complete.isCompleted) complete.complete((written, total));
        },
        onPaused: (_, _) async {},
      ),
      isTrue,
    );

    expect(await complete.future.timeout(const Duration(seconds: 5)), (10, 10));
    expect(await file.readAsBytes(), List<int>.generate(10, (i) => i));
  });
'''
text, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
if count != 1:
    raise SystemExit(f'process relaunch test replacement count={count}')

path.write_text(text)
print('Made unknown-size process-relaunch regression deterministic.')

runtime_path = Path('test/core/services/download_runtime_stability_review_test.dart')
runtime_text = runtime_path.read_text()
old_schema_expectation = "expect(source, contains('kParallelManifestSchemaVersion = 3'));"
new_schema_expectation = "expect(source, contains('kParallelManifestSchemaVersion = 4'));"
if runtime_text.count(old_schema_expectation) != 1:
    raise SystemExit('expected exactly one stale schema v3 runtime assertion')
runtime_path.write_text(runtime_text.replace(old_schema_expectation, new_schema_expectation, 1))
print('Updated runtime manifest schema assertion to v4.')
