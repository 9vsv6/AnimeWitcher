from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}: {old[:160]!r}")
    file.write_text(text.replace(old, new, 1))


parallel = 'lib/core/services/persistent_parallel_download.dart'
runtime_test = 'test/core/services/download_runtime_stability_review_test.dart'
auto_recovery_test = 'test/core/services/persistent_parallel_download_auto_recovery_test.dart'

# A native child is allowed to finish while its logical multipart parent is in
# the non-destructive iOS pause-drain state. Persist that exact completion in
# the plugin DB before releasing the drain slot. Without this checkpoint the
# parent manifest knows the bytes are complete, but a relaunch/explicit resume
# can observe a missing child record and treat the durable Range as ambiguous.
replace_once(
    parallel,
    '''            _markConnectionReady(session, part);\n            _releaseConnection(part);\n            part.complete = true;\n            part.progress = 1;\n            part.credibleProgress = 1;\n            onPartProgress(session.task.taskId, part.task.taskId, 1);\n            await _persist(session);\n            _notifyPausedDrainSettled(session);\n            if (session.active &&\n''',
    '''            _markConnectionReady(session, part);\n            _releaseConnection(part);\n            part.complete = true;\n            part.progress = 1;\n            part.credibleProgress = 1;\n            await saveRecord(\n              TaskRecord(part.task, TaskStatus.complete, 1, part.size),\n            );\n            onPartProgress(session.task.taskId, part.task.taskId, 1);\n            await _persist(session);\n            _notifyPausedDrainSettled(session);\n            if (session.active &&\n''',
)

# The first runtime assertion previously matched the word `originalComplete`
# in explanatory text before the actual callback invocation. Compare against
# the concrete plugin callback statement instead, while preserving the real
# invariant: native transient recovery must run before the plugin can emit its
# terminal failed status.
replace_once(
    runtime_test,
    '''      expect(\n        hook.indexOf('retryBackgroundTransferIfNeeded('),\n        lessThan(hook.indexOf('originalComplete')),\n      );\n''',
    '''      final retryIndex = hook.indexOf('retryBackgroundTransferIfNeeded(');\n      final pluginCallbackIndex = hook.indexOf(\n        'if let original = DownloadUrlSessionHook.originalComplete',\n      );\n      expect(retryIndex, greaterThanOrEqualTo(0));\n      expect(pluginCallbackIndex, greaterThanOrEqualTo(0));\n      expect(retryIndex, lessThan(pluginCallbackIndex));\n''',
)

# The source comment is intentionally wrapped across two Swift comment lines;
# assert the semantic durability boundary rather than a whitespace-sensitive
# phrase that cannot appear contiguously after formatting.
replace_once(
    runtime_test,
    "      expect(section, contains('UI lease telemetry only'));\n",
    "      expect(section, contains('never used as durable resume evidence'));\n",
)

# A permanent HTTP failure has already ended that child's native transport.
# The coordinator now releases the terminal child before parking the logical
# parent, and _pause deliberately touches only still-owned native workers. The
# old test expected a redundant pause() call on the already-failed child. Keep
# the stronger invariant instead: the parent parks, the child is not retried,
# and no destructive transport pause is issued against a terminal worker.
replace_once(
    auto_recovery_test,
    '''      expect(starts, hasLength(1));\n      expect(pauses, contains(child.taskId));\n''',
    '''      expect(starts, hasLength(1));\n      expect(pauses, isEmpty);\n''',
)

print('Closed pause-drain completion and background regression assertion gaps.')
