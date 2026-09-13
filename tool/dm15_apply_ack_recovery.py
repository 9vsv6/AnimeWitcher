from pathlib import Path

path = Path('lib/core/services/download_continued_processing_service.dart')
text = path.read_text()

old_ctor = """  final SystemDownloadChunkUpdate? onChunkUpdate;
  bool _handlerInstalled = false;
"""
new_ctor = """  final SystemDownloadChunkUpdate? onChunkUpdate;
  final bool forceAvailableForTesting;
  bool _handlerInstalled = false;
"""
if new_ctor not in text:
    if old_ctor not in text:
        raise SystemExit('missing forceAvailable field anchor')
    text = text.replace(old_ctor, new_ctor, 1)

old_args = """  DownloadContinuedProcessingService({
    required this.onSystemCancel,
    this.onTaskUpdate,
    this.onChunkUpdate,
  }) {
"""
new_args = """  DownloadContinuedProcessingService({
    required this.onSystemCancel,
    this.onTaskUpdate,
    this.onChunkUpdate,
    @visibleForTesting this.forceAvailableForTesting = false,
  }) {
"""
if new_args not in text:
    if old_args not in text:
        raise SystemExit('missing constructor args anchor')
    text = text.replace(old_args, new_args, 1)

old_available = "  bool get _isAvailable => !kIsWeb && Platform.isIOS;\n"
new_available = "  bool get _isAvailable => forceAvailableForTesting || (!kIsWeb && Platform.isIOS);\n"
if new_available not in text:
    if old_available not in text:
        raise SystemExit('missing availability anchor')
    text = text.replace(old_available, new_available, 1)

old_settlement = """    final snapshotVersion = nextVersion();
    final accepted = await write(snapshotVersion);
    if (accepted == null) return null;
    if (accepted > _nativeQueueSnapshotVersion) {
      _nativeQueueSnapshotVersion = accepted;
    }
    if (accepted == snapshotVersion) return accepted;

    // Native persisted a newer snapshot (for example while Flutter slept).
    // Re-issue this *current* Dart projection above that durable high-water
    // mark instead of silently treating the stale write as successful.
    final retryVersion = nextVersion();
    final retried = await write(retryVersion);
    if (retried != null && retried > _nativeQueueSnapshotVersion) {
      _nativeQueueSnapshotVersion = retried;
    }
    return retried == retryVersion ? retried : null;
"""
new_settlement = """    final snapshotVersion = nextVersion();
    var accepted = await write(snapshotVersion);

    // A lost reply is ambiguous: native may have durably accepted the write.
    // Retry the exact same version once. Native treats an equal version as an
    // idempotent acknowledgement, so this cannot advance or duplicate state.
    if (accepted == null) {
      accepted = await write(snapshotVersion);
    }
    if (accepted == null) return null;

    if (accepted > _nativeQueueSnapshotVersion) {
      _nativeQueueSnapshotVersion = accepted;
    }
    if (accepted == snapshotVersion) return accepted;

    // Native is durably newer (for example it promoted/completed work while
    // Flutter slept). Fail closed. Never relabel this stale Dart payload with
    // a higher version; the caller must rebuild/reconcile a fresh snapshot.
    return null;
"""
if new_settlement not in text:
    if old_settlement not in text:
        raise SystemExit('missing ack settlement anchor')
    text = text.replace(old_settlement, new_settlement, 1)

path.write_text(text)
