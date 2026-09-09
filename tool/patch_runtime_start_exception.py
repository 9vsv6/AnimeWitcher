from pathlib import Path

path = Path('lib/core/services/persistent_parallel_download.dart')
text = path.read_text()
old = '''        if (!await startPart(part.task, part.progress, part.size)) {
          // Native enqueue/resume can fail transiently (especially URLSession
          // hand-off on iOS). Release this socket while it backs off so a
          // healthy tail range can keep the episode moving. The exact taskId
          // and saved bytes stay intact and retry only via this scheduler.
          _stabilizeSessionForRecovery(session);
          _schedulePartRecovery(session, part);
          await _status(session, TaskStatus.running);
          return true;
        }
'''
new = '''        bool started;
        try {
          started = await startPart(part.task, part.progress, part.size);
        } catch (_) {
          // An enqueue exception happens after this child reserved its scheduler
          // slot but before native ownership exists. Release that exact slot and
          // retry the same immutable Range/taskId; never pause the parent and
          // never leave currentBatchPendingIds blocking the next pump forever.
          _stabilizeSessionForRecovery(session);
          _schedulePartRecovery(session, part);
          try {
            await _status(session, TaskStatus.running);
          } catch (_) {}
          return true;
        }
        if (!started) {
          // Native enqueue/resume can fail transiently (especially URLSession
          // hand-off on iOS). Release this socket while it backs off so a
          // healthy tail range can keep the episode moving. The exact taskId
          // and saved bytes stay intact and retry only via this scheduler.
          _stabilizeSessionForRecovery(session);
          _schedulePartRecovery(session, part);
          await _status(session, TaskStatus.running);
          return true;
        }
'''
if text.count(old) != 1:
    raise SystemExit(f'expected one startPart block, found {text.count(old)}')
path.write_text(text.replace(old, new, 1))
print('fixed thrown native enqueue recovery')
