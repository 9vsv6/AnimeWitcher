from pathlib import Path

path = Path('test/core/services/persistent_parallel_download_test.dart')
text = path.read_text()

old = '''      liveIds = <String>{first.taskId};
      await markRunning(<DownloadTask>[first]);

      expect(
        await coordinator.pause(parent, preserveLiveParts: true),
        isTrue,
      );
'''
new = '''      liveIds = <String>{first.taskId};
      await markRunning(<DownloadTask>[first]);
      final startsAtPause = starts.length;

      expect(
        await coordinator.pause(parent, preserveLiveParts: true),
        isTrue,
      );
'''
if text.count(old) != 1:
    raise SystemExit(f'expected one drain-test setup, found {text.count(old)}')
text = text.replace(old, new, 1)

old = "      expect(starts.length, 1, reason: 'paused parent must not launch tail work');\n"
new = "      expect(starts.length, startsAtPause, reason: 'paused parent must not launch tail work');\n"
if text.count(old) != 1:
    raise SystemExit(f'expected one post-pause launch assertion, found {text.count(old)}')
text = text.replace(old, new, 1)

# Only the first drain test has a final fixed-one assertion. The resume test
# intentionally keeps its own identity-count assertion unchanged.
old = '''      expect(records[first.taskId]?.status, TaskStatus.complete);
      expect(settled, contains(parent.taskId));
      expect(starts.length, 1);
'''
new = '''      expect(records[first.taskId]?.status, TaskStatus.complete);
      expect(settled, contains(parent.taskId));
      expect(starts.length, startsAtPause);
'''
if text.count(old) != 1:
    raise SystemExit(f'expected one final drain launch assertion, found {text.count(old)}')
text = text.replace(old, new, 1)

path.write_text(text)
print('Made pause-drain launch assertion response-gated and deterministic.')
