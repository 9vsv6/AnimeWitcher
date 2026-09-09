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
new = '''        void rollbackUnownedReservation() {
          // Reservation happens before startPart to close the enqueue/running
          // race. If native never accepts the child, put that slot back into
          // the same slow-start batch. Otherwise repeated transient enqueue
          // failures consume the batch counter and can strand the episode with
          // no launchable work even though its immutable Range still exists.
          if (session.currentBatchPendingIds.remove(part.task.taskId)) {
            session.currentBatchRemaining++;
          }
          _activeConnectionIds.remove(part.task.taskId);
          part.launched = false;
        }

        bool started;
        try {
          started = await startPart(part.task, part.progress, part.size);
        } catch (_) {
          // The task was never handed to native IO. This is a local enqueue
          // failure, not evidence that the origin cannot sustain the current
          // connection level. Restoring/capping slow-start here can pin the
          // session at its already-active connection count and silently prevent
          // this Range from ever being retried.
          rollbackUnownedReservation();
          _schedulePartRecovery(session, part);
          try {
            await _status(session, TaskStatus.running);
          } catch (_) {}
          return true;
        }
        if (!started) {
          // A false enqueue result has identical ownership semantics: no native
          // worker exists, so restore the scheduler reservation and retry the
          // exact same taskId/Range without teaching a lower host ceiling.
          rollbackUnownedReservation();
          _schedulePartRecovery(session, part);
          await _status(session, TaskStatus.running);
          return true;
        }
'''
if text.count(old) != 1:
    raise SystemExit(f'expected one startPart block, found {text.count(old)}')
path.write_text(text.replace(old, new, 1))
print('fixed pre-native enqueue recovery without false host backoff')
