from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one match, found {count}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1))


parallel = 'lib/core/services/persistent_parallel_download.dart'

# A deterministic byte-integrity failure is not transient coordinator
# bookkeeping. Park the logical episode and preserve every child file rather
# than leaving the parent "running" forever while recovery keeps rediscovering
# the same impossible state.
replace_once(
    parallel,
    """          if (part.complete) throw StateError('A completed part is missing');
""",
    """          if (part.complete) {
            await _pause(session);
            return false;
          }
""",
)

replace_once(
    parallel,
    """            if (!exists || length != part.size) {
              throw StateError(
                'Invalid byte count for part ${part.task.taskId}',
              );
            }
""",
    """            if (!exists || length != part.size) {
              // A completed callback with the wrong durable byte count is a
              // data-integrity boundary, not a coordinator race. Keep the
              // bytes for diagnosis/resume and park the parent deterministically.
              await _pause(session);
              return;
            }
""",
)

replace_once(
    parallel,
    """      // Never overwrite an unexpected user-visible file during automatic
      // recovery. The user can remove/rename it explicitly and resume later.
      throw StateError('Download target already exists with a different size');
""",
    """      // Never overwrite an unexpected user-visible file during automatic
      // recovery. The user can remove/rename it explicitly and resume later.
      await _pause(session);
      return;
""",
)

replace_once(
    parallel,
    """        if (!await file.exists() || await file.length() != part.size) {
          throw StateError('Part size changed');
        }
""",
    """        if (!await file.exists() || await file.length() != part.size) {
          await _pause(session);
          return;
        }
""",
)

replace_once(
    parallel,
    """          if (assembledBytes + bytes.length > session.size) {
            throw StateError('Assembly exceeded expected size');
          }
""",
    """          if (assembledBytes + bytes.length > session.size) {
            await _pause(session);
            return;
          }
""",
)

replace_once(
    parallel,
    """      if (assembledBytes != session.size) {
        throw StateError('Incomplete assembly');
      }
""",
    """      if (assembledBytes != session.size) {
        await _pause(session);
        return;
      }
""",
)

replace_once(
    parallel,
    """    if (!await staging.exists() || await staging.length() != session.size) {
      throw StateError('Incomplete assembly');
    }
""",
    """    if (!await staging.exists() || await staging.length() != session.size) {
      await _pause(session);
      return;
    }
""",
)

# The multipart aggregate intentionally ignores a one-burst native speed. The
# stable rolling telemetry unit tests cover exact speed/ETA math over a real
# observation window; this integration test should assert that one callback
# burst does not recreate the old spike.
replace_once(
    'test/core/services/persistent_parallel_download_progress_test.dart',
    """      expect(aggregate.networkSpeed, closeTo(0.5, 0.000001));
      // 1.5 MB remains at an aggregate 0.5 MB/s.
      expect(aggregate.timeRemaining, const Duration(seconds: 3));
""",
    """      expect(
        aggregate.networkSpeed,
        0,
        reason: 'a sub-second multipart callback burst is not a stable speed',
      );
      expect(aggregate.timeRemaining, Duration.zero);
""",
)

# Screenshot artifacts are diagnostic only. /opt/cursor is writable in some
# local/dev images but not on the macOS GitHub runner used for the iOS compile
# gate, so use the platform temp directory instead of making unrelated widget
# tests depend on a privileged absolute path.
replace_once(
    'test/features/comments/presentation/animewitcher_replies_screen_test.dart',
    """  final artifacts = Directory('/opt/cursor/artifacts');
""",
    """  final artifacts = Directory(
    '${Directory.systemTemp.path}/animewitcher-test-artifacts',
  );
""",
)

print('full-suite runtime follow-up patch applied')
