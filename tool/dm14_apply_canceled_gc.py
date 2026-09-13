from pathlib import Path

path = Path('lib/core/services/download_service.dart')
text = path.read_text()
old = """      final restored = job.restoreTaskSnapshot();
      if (restored != null) {
        try {
          final path = await restored.filePath();"""
new = """      final restored = job.restoreTaskSnapshot();
      if (restored is ParallelDownloadTask) {
        try {
          // The canceled tombstone plus notOwned runtime state proves the
          // logical attempt is obsolete. Let the multipart owner settle its
          // exact child identities before deleting its manifest/part files.
          await _parallel.cancel(restored);
        } catch (_) {
          // Preserve both the tombstone and artifacts when child ownership
          // cannot be settled. A later recovery pass can retry safely.
          continue;
        }
      }
      if (restored != null) {
        try {
          final path = await restored.filePath();"""

if new in text:
    print('DM-14 canceled multipart GC GREEN already present')
elif old in text:
    path.write_text(text.replace(old, new, 1))
    print('Applied DM-14 canceled multipart GC GREEN')
else:
    raise SystemExit('missing DM-14 tombstone GC anchor')
