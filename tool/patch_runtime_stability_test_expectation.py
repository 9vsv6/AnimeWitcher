from pathlib import Path

path = Path('test/core/services/persistent_parallel_download_test.dart')
text = path.read_text()
old = '''  test(\n    'a pump enqueue exception parks the parent and releases all slots',\n    () async {\n      await coordinator.start(parent, 25);\n      throwStarts = true;\n      await markRunning(starts.take(1));\n      await waitUntil(() => statuses.last == TaskStatus.paused);\n      expect(coordinator.isActive(parent.taskId), isFalse);\n      expect(coordinator.activeConnectionCount, 0);\n      throwStarts = false;\n      starts.clear();\n      expect(await coordinator.start(parent, 25), isTrue);\n      await expandFreshTo(5);\n    },\n  );\n'''
new = '''  test(\n    'a pump enqueue exception recovers without pausing the logical parent',\n    () async {\n      await coordinator.start(parent, 25);\n      throwStarts = true;\n      await markRunning(starts.take(1));\n      await Future<void>.delayed(const Duration(milliseconds: 35));\n      expect(coordinator.isActive(parent.taskId), isTrue);\n      expect(statuses, isNot(contains(TaskStatus.paused)));\n\n      throwStarts = false;\n      final beforeRecovery = starts.length;\n      await waitUntil(() => starts.length > beforeRecovery);\n      await markRunning(starts.skip(beforeRecovery));\n      expect(coordinator.isActive(parent.taskId), isTrue);\n      expect(statuses, isNot(contains(TaskStatus.paused)));\n    },\n  );\n'''
if text.count(old) != 1:
    raise SystemExit(f'expected one old pump-exception test, found {text.count(old)}')
path.write_text(text.replace(old, new, 1))
print('updated persistent coordinator recovery expectation')
