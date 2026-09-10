from pathlib import Path

path = Path('test/core/services/persistent_parallel_download_test.dart')
text = path.read_text()

# markRunning() acknowledges the first slow-start batch and can schedule the
# next batch on a microtask. Capture the launch count only after pause() has
# committed its inactive boundary; the invariant is that no *new* child starts
# after that boundary, not that slow-start could never have raced immediately
# before it.
old = '''      expect(
        await coordinator.pause(parent, preserveLiveParts: true),
        isTrue,
      );
      expect(pauses, isEmpty);
      expect(coordinator.isActive(parent.taskId), isFalse);
      expect(coordinator.activeConnectionCount, 1);
      expect(statuses.last, TaskStatus.paused);
      expect(starts.length, 1, reason: 'paused parent must not launch tail work');

      await completePart(first, <int>[0, 1, 2, 3, 4]);
      await waitUntil(() => coordinator.activeConnectionCount == 0);
      expect(records[first.taskId]?.status, TaskStatus.complete);
      expect(settled, contains(parent.taskId));
      expect(starts.length, 1);
'''
new = '''      expect(
        await coordinator.pause(parent, preserveLiveParts: true),
        isTrue,
      );
      final startsAfterPause = starts.length;
      expect(pauses, isEmpty);
      expect(coordinator.isActive(parent.taskId), isFalse);
      expect(coordinator.activeConnectionCount, 1);
      expect(statuses.last, TaskStatus.paused);

      await completePart(first, <int>[0, 1, 2, 3, 4]);
      await waitUntil(() => coordinator.activeConnectionCount == 0);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(records[first.taskId]?.status, TaskStatus.complete);
      expect(settled, contains(parent.taskId));
      expect(
        starts.length,
        startsAfterPause,
        reason: 'inactive paused parent must not schedule tail work',
      );
'''
if text.count(old) != 1:
    # A previous correction run may have inserted startsAtPause. Normalize that
    # generated variant too so this script stays idempotent across CI retries.
    old = '''      final startsAtPause = starts.length;

      expect(
        await coordinator.pause(parent, preserveLiveParts: true),
        isTrue,
      );
      expect(pauses, isEmpty);
      expect(coordinator.isActive(parent.taskId), isFalse);
      expect(coordinator.activeConnectionCount, 1);
      expect(statuses.last, TaskStatus.paused);
      expect(starts.length, startsAtPause, reason: 'paused parent must not launch tail work');

      await completePart(first, <int>[0, 1, 2, 3, 4]);
      await waitUntil(() => coordinator.activeConnectionCount == 0);
      expect(records[first.taskId]?.status, TaskStatus.complete);
      expect(settled, contains(parent.taskId));
      expect(starts.length, startsAtPause);
'''
if text.count(old) != 1:
    raise SystemExit(f'expected one pause-drain assertion block, found {text.count(old)}')
text = text.replace(old, new, 1)

path.write_text(text)
print('Made pause-drain launch assertion deterministic at the committed pause boundary.')
