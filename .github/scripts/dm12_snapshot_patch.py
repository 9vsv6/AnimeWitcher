from pathlib import Path

service_path = Path('lib/core/services/download_service.dart')
provider_path = Path('lib/features/library/presentation/downloads_provider.dart')
service = service_path.read_text()
provider = provider_path.read_text()

snapshot_class = '''class DownloadLogicalSnapshot {
  const DownloadLogicalSnapshot({
    required this.task,
    required this.status,
    required this.progress,
    required this.metadata,
    required this.logicalState,
  });

  final DownloadTask task;
  final TaskStatus status;
  final double progress;
  final Map<String, dynamic> metadata;
  final DownloadJobState? logicalState;
}

'''
class_anchor = 'class DownloadProgressData {'
if snapshot_class not in service:
    if class_anchor not in service:
        raise SystemExit('snapshot class anchor missing')
    service = service.replace(class_anchor, snapshot_class + class_anchor, 1)

old_logical = '''  /// Read-only logical lifecycle projection for UI surfaces. Executor/plugin
  /// status remains evidence and must not overwrite a durable JobStore state.
  Future<DownloadJobState?> logicalJobStateForTask(String taskId) async {
    final id = taskId.trim();
    if (id.isEmpty) return null;
    return (await _jobStore.get(id))?.state;
  }
'''
new_logical = '''  /// Read-only logical lifecycle projection for UI surfaces. Executor/plugin
  /// status remains evidence and must not overwrite a durable JobStore state.
  Future<DownloadJobState?> logicalJobStateForTask(String taskId) async {
    final id = taskId.trim();
    if (id.isEmpty) return null;
    return (await _jobStore.get(id))?.state;
  }

  /// Service-owned projection used by presentation. The plugin database and
  /// Hive metadata remain executor/persistence replicas and are merged here,
  /// behind the lifecycle authority, rather than in a UI provider.
  Future<List<DownloadLogicalSnapshot>> logicalDownloadSnapshots() async {
    final snapshots = <DownloadLogicalSnapshot>[];
    final seen = <String>{};
    final records = await FileDownloader().database.allRecords();

    for (final record in records) {
      final task = record.task;
      if (task is! DownloadTask || !seen.add(task.taskId)) continue;
      final snapshot = await logicalDownloadSnapshotForTask(
        task,
        executorStatus: record.status,
        executorProgress: record.progress,
      );
      if (snapshot != null) snapshots.add(snapshot);
    }

    // A durable waiter can exist before/without a plugin database row. Include
    // its persisted task descriptor so startup and queue-overflow rows remain
    // visible without making presentation inspect persistence directly.
    for (final job in await _jobStore.all()) {
      if (!seen.add(job.taskId) ||
          job.state == DownloadJobState.canceled ||
          job.state == DownloadJobState.orphaned) {
        continue;
      }
      final task = job.restoreTaskSnapshot();
      if (task == null) continue;
      final snapshot = await logicalDownloadSnapshotForTask(
        task,
        executorStatus: downloadJobDisplayStatus(job.state),
        executorProgress: job.state == DownloadJobState.completed ? 1.0 : 0.0,
      );
      if (snapshot != null) snapshots.add(snapshot);
    }
    return snapshots;
  }

  Future<DownloadLogicalSnapshot?> logicalDownloadSnapshotForTask(
    Task task, {
    TaskStatus? executorStatus,
    double executorProgress = 0.0,
  }) async {
    if (task is! DownloadTask) return null;
    final id = task.taskId.trim();
    if (id.isEmpty) return null;

    final job = await _jobStore.get(id);
    final logicalState = job?.state;
    if (logicalState == DownloadJobState.canceled ||
        logicalState == DownloadJobState.orphaned) {
      return null;
    }

    var status = executorStatus ?? TaskStatus.enqueued;
    var progress = executorProgress;
    if (logicalState != null) {
      status = downloadJobDisplayStatus(logicalState);
      if (progress < 0 || progress > 1) {
        progress = logicalState == DownloadJobState.completed ? 1.0 : 0.0;
      }
    } else {
      // Pre-JobStore migration fallback is contained in the service seam.
      if (status == TaskStatus.canceled) return null;
      if (status == TaskStatus.failed || status == TaskStatus.notFound) {
        status = TaskStatus.paused;
        if (progress < 0 || progress > 1) progress = 0.0;
      } else if (progress < 0 || progress > 1) {
        progress = status == TaskStatus.complete ? 1.0 : 0.0;
      }
    }

    final metadata = await _ref
        .read(storageServiceProvider)
        .getDownloadMetadata(id);
    if (metadata == null) return null;
    return DownloadLogicalSnapshot(
      task: task,
      status: status,
      progress: progress.clamp(0.0, 1.0).toDouble(),
      metadata: metadata,
      logicalState: logicalState,
    );
  }
'''
if 'Future<List<DownloadLogicalSnapshot>> logicalDownloadSnapshots()' not in service:
    if service.count(old_logical) != 1:
        raise SystemExit(f'logical snapshot anchor mismatch: {service.count(old_logical)}')
    service = service.replace(old_logical, new_logical, 1)

provider = provider.replace(
    "import 'package:animewitcher/core/storage/storage_service.dart';\n",
    '',
    1,
)

refresh_start = provider.find('  Future<List<DownloadItem>> _refreshList() async {')
refresh_end = provider.find('  List<DownloadItem> _orderDownloads(', refresh_start)
if refresh_start < 0 or refresh_end < 0:
    raise SystemExit('provider refresh anchors missing')
new_refresh = '''  Future<List<DownloadItem>> _refreshList() async {
    final downloadService = ref.read(downloadServiceProvider);
    final snapshots = await downloadService.logicalDownloadSnapshots();
    final items = <DownloadItem>[];

    for (final snapshot in snapshots) {
      final item = downloadItemFromTaskMetadata(
        task: snapshot.task,
        status: snapshot.status,
        metadata: snapshot.metadata,
        logicalState: snapshot.logicalState,
        progress: snapshot.progress,
      );
      if (item == null) continue;
      items.add(item);
      if (snapshot.status == TaskStatus.complete) {
        unawaited(
          ensureDownloadedEpisodeArtwork(
            taskId: item.id,
            episode: item.episode,
          ),
        );
      }
    }

    // A user-deleted task is a session tombstone until its service-owned
    // cleanup has settled. Never let an unrelated refresh resurrect it.
    items.removeWhere((item) => _deletingIds.contains(item.id));
    items.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final collapsed = collapseDuplicateDownloads(items);
    return _orderDownloads(collapsed.visible);
  }

'''
if 'final snapshots = await downloadService.logicalDownloadSnapshots();' not in provider:
    provider = provider[:refresh_start] + new_refresh + provider[refresh_end:]

old_new_row = '''        final metadata = await ref
            .read(storageServiceProvider)
            .getDownloadMetadata(update.task.taskId);
        final incoming = metadata == null
            ? null
            : downloadItemFromTaskMetadata(
                task: update.task,
                status: projectedStatus,
                metadata: metadata,
                logicalState: logicalState,
              );
'''
new_new_row = '''        final snapshot = await ref
            .read(downloadServiceProvider)
            .logicalDownloadSnapshotForTask(
              update.task,
              executorStatus: projectedStatus,
            );
        final incoming = snapshot == null
            ? null
            : downloadItemFromTaskMetadata(
                task: snapshot.task,
                status: snapshot.status,
                metadata: snapshot.metadata,
                logicalState: snapshot.logicalState,
                progress: snapshot.progress,
              );
'''
if '.logicalDownloadSnapshotForTask(' not in provider:
    if provider.count(old_new_row) != 1:
        raise SystemExit(f'new-row snapshot anchor mismatch: {provider.count(old_new_row)}')
    provider = provider.replace(old_new_row, new_new_row, 1)

service_path.write_text(service)
provider_path.write_text(provider)
