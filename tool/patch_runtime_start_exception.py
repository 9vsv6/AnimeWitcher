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
          // The task was never handed to native IO. Retry this exact taskId and
          // byte Range after backoff; never pause the logical episode or reset
          // any durable bytes.
          rollbackUnownedReservation();
          _stabilizeSessionForRecovery(session);
          _schedulePartRecovery(session, part);
          try {
            await _status(session, TaskStatus.running);
          } catch (_) {}
          return true;
        }
        if (!started) {
          // A false enqueue result has the same ownership semantics as a throw:
          // native never acquired the reserved slot, so restore its batch count
          // before scheduling the same child for recovery.
          rollbackUnownedReservation();
          _stabilizeSessionForRecovery(session);
          _schedulePartRecovery(session, part);
          await _status(session, TaskStatus.running);
          return true;
        }
'''
if text.count(old) != 1:
    raise SystemExit(f'expected one startPart block, found {text.count(old)}')
path.write_text(text.replace(old, new, 1))
print('fixed native enqueue reservation recovery')
