from pathlib import Path


def replace_one(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    return text.replace(old, new, 1)

# PersistentParallelDownload: replace an expired source without touching parts.
pp_path = Path('lib/core/services/persistent_parallel_download.dart')
pp = pp_path.read_text()
pp = replace_one(
    pp,
    "  double? progressFor(String id) => _sessions[id]?.progress;\n\n  /// Includes native tasks",
    """  double? progressFor(String id) => _sessions[id]?.progress;

  /// Replace only the remote source of a paused/restored multipart job.
  /// Every range identity, byte boundary, credible progress value and local
  /// part file is retained. This is used when a signed CDN URL expires.
  Future<ParallelDownloadTask?> replaceSource(
    ParallelDownloadTask task, {
    required String url,
    required Map<String, String> headers,
  }) async {
    if (_disposed || !await restore(task)) return null;
    final session = _sessions[task.taskId]!;
    return session.serialize(() async {
      if (_disposed || session.deleted || session.active) return null;
      final updated = task.copyWith(
        url: url,
        headers: Map<String, String>.from(headers),
      );
      if (updated is! ParallelDownloadTask) return null;
      session.task = updated;
      for (final part in session.parts) {
        final childHeaders = Map<String, String>.from(headers)
          ..removeWhere(
            (key, _) =>
                key.toLowerCase() == 'range' ||
                key.toLowerCase() == 'if-range',
          );
        childHeaders['Range'] = 'bytes=${part.from}-${part.to}';
        childHeaders['Accept-Encoding'] = 'identity';
        part.task = part.task.copyWith(
          url: url,
          headers: childHeaders,
          retries: kDownloadPartRetries,
        );
      }
      await _persist(session);
      final record = await recordForId(task.taskId);
      await saveRecord(
        TaskRecord(
          session.task,
          record?.status ?? TaskStatus.paused,
          session.progress,
          session.size,
        ),
      );
      return session.task;
    });
  }

  /// Includes native tasks""",
    'multipart source replacement',
)
pp = replace_one(
    pp,
    "class _ParallelSession {\n  _ParallelSession(this.task, this.manifest, this.parts);\n\n  final ParallelDownloadTask task;",
    "class _ParallelSession {\n  _ParallelSession(this.task, this.manifest, this.parts);\n\n  ParallelDownloadTask task;",
    'mutable parent source',
)
pp = replace_one(
    pp,
    "  final DownloadTask task;\n  final int from;",
    "  DownloadTask task;\n  final int from;",
    'mutable child source',
)
pp_path.write_text(pp)

# DownloadService: durable job state + host profiles + signed URL refresh.
path = Path('lib/core/services/download_service.dart')
text = path.read_text()
text = replace_one(
    text,
    "import 'download_range_transfer.dart';\nimport 'download_transport.dart';",
    "import 'download_range_transfer.dart';\nimport 'download_retry_policy.dart';\nimport 'download_host_profile.dart';\nimport 'download_job_state.dart';\nimport 'download_job_store.dart';\nimport 'download_url_refresh.dart';\nimport 'download_transport.dart';",
    'reliability imports',
)
text = replace_one(
    text,
    "  late final DownloadRangeTransfer _rangeTransfers;\n  late final NativeSingleDownloadTransport _nativeTransport;",
    "  late final DownloadRangeTransfer _rangeTransfers;\n  late final NativeSingleDownloadTransport _nativeTransport;\n  late final DownloadHostProfileStore _hostProfiles;\n  late final DownloadJobStore _jobStore;",
    'reliability fields',
)
text = replace_one(
    text,
    "  DownloadService(this._ref) : _dio = _ref.read(dioClientProvider) {\n    _nativeTransport = NativeSingleDownloadTransport();\n    _rangeTransfers = DownloadRangeTransfer(_dio);\n    _parallel = PersistentParallelDownload(",
    """  DownloadService(this._ref) : _dio = _ref.read(dioClientProvider) {
    _nativeTransport = NativeSingleDownloadTransport();
    _rangeTransfers = DownloadRangeTransfer(_dio);
    _hostProfiles = DownloadHostProfileStore(
      const HiveDownloadHostProfileBackend(),
    );
    _jobStore = DownloadJobStore(const HiveDownloadJobBackend());
    _parallel = PersistentParallelDownload(""",
    'reliability construction',
)
text = replace_one(
    text,
    "      onPartProgress: (parent, child, progress) {\n        if (!_disposed)\n          _handleNativeChunkUpdate(\n            parentTaskId: parent,\n            chunkTaskId: child,\n            progress: progress,\n          );\n      },\n    );",
    """      onPartProgress: (parent, child, progress) {
        if (!_disposed)
          _handleNativeChunkUpdate(
            parentTaskId: parent,
            chunkTaskId: child,
            progress: progress,
          );
      },
      onHostPressure: (url, ceiling) {
        unawaited(
          _hostProfiles.recordPressure(
            url: url,
            fallbackCeiling: ceiling,
          ),
        );
      },
      onHostSample: (url, connections, bytesPerSecond) {
        unawaited(
          _hostProfiles.recordSuccess(
            url: url,
            activeConnections: connections,
            bytesPerSecond: bytesPerSecond,
          ),
        );
      },
    );""",
    'parallel host callbacks',
)
text = replace_one(
    text,
    "    // Restore part identities before replaying native callbacks.\n    for (final record in await FileDownloader().database.allRecords()) {",
    """    // Restore persisted host knowledge before any multipart session picks
    // its slow-start target. Expired profiles are removed by the store.
    _parallel.seedHostCeilings(await _hostProfiles.validHostCeilings());

    // Restore part identities before replaying native callbacks.
    for (final record in await FileDownloader().database.allRecords()) {""",
    'seed host profiles',
)
# Fresh logical job creation.
text = replace_one(
    text,
    "        final transferTask = await _adaptiveTaskForFreshStart(\n          task,\n          knownTotalBytes: expectedBytes,\n        );\n\n        _waitingPayloads[transferTask.taskId]",
    """        final transferTask = await _adaptiveTaskForFreshStart(
          task,
          knownTotalBytes: expectedBytes,
        );
        await _jobStore.put(
          DownloadJobRecord(
            taskId: transferTask.taskId,
            trackingUrl: trackingUrl ?? url,
            state: startNow
                ? DownloadJobState.starting
                : DownloadJobState.queued,
            generation: 0,
            durableBytes: 0,
            expectedBytes: expectedBytes,
            userPaused: false,
            queueWaiting: !startNow,
            updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
            fingerprint: DownloadResourceFingerprint(
              expectedBytes: expectedBytes,
              finalUrl: url,
            ),
          ),
        );

        _waitingPayloads[transferTask.taskId]""",
    'fresh durable job',
)
# Explicit delete is the only path that removes durable job/refresh identity.
text = replace_one(
    text,
    "        await FileDownloader().database.deleteRecordWithId(taskId);\n        await _ref.read(storageServiceProvider).removeDownloadMetadata(taskId);\n        await _syncQueueToCapUnlocked();",
    """        await FileDownloader().database.deleteRecordWithId(taskId);
        await _ref.read(storageServiceProvider).removeDownloadMetadata(taskId);
        await _jobStore.remove(taskId);
        await _ref
            .read(downloadUrlRefreshStoreProvider)
            .remove(trackingUrl);
        await _syncQueueToCapUnlocked();""",
    'delete durable identities',
)
# Completed missing-file record must allow a truly fresh logical job next time.
text = replace_one(
    text,
    "      await FileDownloader().database.deleteRecordWithId(record.task.taskId);\n      await storage.removeDownloadMetadata(record.task.taskId);",
    """      await FileDownloader().database.deleteRecordWithId(record.task.taskId);
      await storage.removeDownloadMetadata(record.task.taskId);
      await _jobStore.remove(record.task.taskId);""",
    'drop stale complete job',
)
# Resume refresh before deciding native-vs-partial execution.
text = replace_one(
    text,
    "    final saved = await _savedProgressFor(task);\n    final trackingUrl = downloadTrackingUrl(task);",
    """    final saved = await _savedProgressFor(task);
    final refreshResult = await _refreshTaskBeforeResume(
      task,
      expectedBytes: saved.totalSize,
      partialBytes: saved.partialBytes,
    );
    task = refreshResult.task;
    final trackingUrl = downloadTrackingUrl(task);""",
    'refresh before resume',
)
text = replace_one(
    text,
    "    if (task is ParallelDownloadTask) {\n      if (await _parallel.restore(task))",
    """    if (task is ParallelDownloadTask) {
      if (await _parallel.restore(task))""",
    'parallel resume anchor',
)
text = replace_one(
    text,
    "    return resumeOrRestartDownload(\n      canResume: () async {",
    """    // A refreshed signed URL cannot use native resume data that embeds the
    // expired URL. When a verified partial file exists, go directly to the
    // prefix-validated Range append path.
    if (refreshResult.refreshed && saved.partialBytes > 0) {
      return _resumeUsingPartialFile(task);
    }

    return resumeOrRestartDownload(
      canResume: () async {""",
    'refreshed partial path',
)
# Replace the Range adapter with a generation-fenced async version.
old_range = """  Future<bool> _appendRemainingWithDio(
    DownloadTask task, {
    required File dest,
    required int existingBytes,
    required int expectedBytes,
  }) => _rangeTransfers.start(
    id: task.taskId,
    url: task.url,
    headers: task.headers,
    file: dest,
    existingBytes: existingBytes,
    expectedBytes: expectedBytes,
    onState: (written, total, complete) async {
      if (_disposed) return;
      final status = complete ? TaskStatus.complete : TaskStatus.running;
      await FileDownloader().database.updateRecord(
        TaskRecord(task, status, written / total, total),
      );
      _sharedEvents.add(TaskProgressUpdate(task, written / total, total));
      if (complete)
        _sharedEvents.add(TaskStatusUpdate(task, TaskStatus.complete));
    },
    onPaused: (written, total) async {
      if (_disposed) return;
      await FileDownloader().database.updateRecord(
        TaskRecord(task, TaskStatus.paused, written / total, total),
      );
      _sharedEvents.add(TaskStatusUpdate(task, TaskStatus.paused));
    },
  );
"""
new_range = """  Future<bool> _appendRemainingWithDio(
    DownloadTask task, {
    required File dest,
    required int existingBytes,
    required int expectedBytes,
  }) async {
    final logical = isLogicalEpisodeDownloadTask(task);
    DownloadAttemptToken? token;
    var canRefreshUrl = false;
    if (logical) {
      token = await _beginLogicalRangeAttempt(
        task,
        existingBytes: existingBytes,
        expectedBytes: expectedBytes,
      );
      canRefreshUrl =
          await _ref
              .read(downloadUrlRefreshStoreProvider)
              .get(downloadTrackingUrl(task)) !=
          null;
    }

    return _rangeTransfers.start(
      id: task.taskId,
      url: task.url,
      headers: task.headers,
      file: dest,
      existingBytes: existingBytes,
      expectedBytes: expectedBytes,
      canRefreshUrl: canRefreshUrl,
      onState: (written, total, complete) async {
        if (_disposed) return;
        if (token != null &&
            !await _jobStore.updateForAttempt(
              token,
              state: complete
                  ? DownloadJobState.completed
                  : DownloadJobState.running,
              durableBytes: written,
              expectedBytes: total,
              queueWaiting: false,
            )) {
          return;
        }
        final status = complete ? TaskStatus.complete : TaskStatus.running;
        await FileDownloader().database.updateRecord(
          TaskRecord(task, status, written / total, total),
        );
        _sharedEvents.add(TaskProgressUpdate(task, written / total, total));
        if (complete) {
          _sharedEvents.add(TaskStatusUpdate(task, TaskStatus.complete));
        }
      },
      onPaused: (written, total) async {
        if (_disposed) return;
        if (token != null &&
            !await _jobStore.updateForAttempt(
              token,
              state: _userPausedIds.contains(task.taskId)
                  ? DownloadJobState.pausedByUser
                  : DownloadJobState.interrupted,
              durableBytes: written,
              expectedBytes: total,
            )) {
          return;
        }
        await FileDownloader().database.updateRecord(
          TaskRecord(task, TaskStatus.paused, written / total, total),
        );
        _sharedEvents.add(TaskStatusUpdate(task, TaskStatus.paused));
      },
      onFailure: (failure) async {
        if (!logical || token == null || !await _jobStore.accepts(token)) return;
        if (failure.action == DownloadFailureAction.refreshUrl) {
          // DownloadRangeTransfer removes its ownership immediately after this
          // callback returns. Queue the retry on the next event turn so the
          // same taskId can start a new fenced generation safely.
          Future<void>.delayed(Duration.zero, () async {
            if (_disposed ||
                _userPausedIds.contains(task.taskId) ||
                _cancellingUrls.contains(downloadTrackingUrl(task))) {
              return;
            }
            await _serializeQueue(() async {
              final record = await FileDownloader().database.recordForId(
                task.taskId,
              );
              if (record?.task is DownloadTask) {
                await _resumeDownloadTask(record!.task as DownloadTask);
              }
            });
          });
        } else if (failure.action == DownloadFailureAction.reconcileRange &&
            failure.resourceSize > 0 &&
            await dest.exists() &&
            await dest.length() == failure.resourceSize &&
            (expectedBytes <= 0 || expectedBytes == failure.resourceSize)) {
          await _jobStore.updateForAttempt(
            token,
            state: DownloadJobState.completed,
            durableBytes: failure.resourceSize,
            expectedBytes: failure.resourceSize,
          );
          await FileDownloader().database.updateRecord(
            TaskRecord(task, TaskStatus.complete, 1, failure.resourceSize),
          );
          _sharedEvents.add(
            TaskProgressUpdate(task, 1, failure.resourceSize),
          );
          _sharedEvents.add(TaskStatusUpdate(task, TaskStatus.complete));
        }
      },
    );
  }

  Future<DownloadAttemptToken?> _beginLogicalRangeAttempt(
    DownloadTask task, {
    required int existingBytes,
    required int expectedBytes,
  }) async {
    final trackingUrl = downloadTrackingUrl(task);
    var job = await _jobStore.get(task.taskId);
    if (job == null) {
      final seeded = DownloadJobRecord(
        taskId: task.taskId,
        trackingUrl: trackingUrl,
        state: DownloadJobState.interrupted,
        generation: 0,
        durableBytes: existingBytes,
        expectedBytes: expectedBytes,
        userPaused: false,
        queueWaiting: false,
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        fingerprint: DownloadResourceFingerprint(
          expectedBytes: expectedBytes,
          finalUrl: task.url,
        ),
      );
      if (!await _jobStore.put(seeded)) return null;
      job = seeded;
    } else if (existingBytes > job.durableBytes) {
      await _jobStore.put(
        job.copyWith(
          durableBytes: existingBytes,
          expectedBytes: expectedBytes > 0 ? expectedBytes : job.expectedBytes,
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    return _jobStore.beginAttempt(
      task.taskId,
      state: DownloadJobState.running,
    );
  }

  Future<({DownloadTask task, bool refreshed})> _refreshTaskBeforeResume(
    DownloadTask task, {
    required int expectedBytes,
    required int partialBytes,
  }) async {
    // Native single-file resume data may be the only durable representation of
    // its bytes. Do not replace that URL unless a visible partial prefix exists.
    // Multipart manifests own their own durable child files, so they are safe.
    if (task is! ParallelDownloadTask && partialBytes <= 0) {
      return (task: task, refreshed: false);
    }

    final trackingUrl = downloadTrackingUrl(task);
    final store = _ref.read(downloadUrlRefreshStoreProvider);
    final descriptor = await store.get(trackingUrl);
    if (descriptor == null) return (task: task, refreshed: false);

    // Keep a still-valid URL. This avoids provider extraction work on every
    // short pause/resume while still detecting expired signed links.
    final current = await getMetadata(task.url, headers: task.headers);
    final currentSizeMatches =
        expectedBytes <= 0 || current?.size == null || current?.size == expectedBytes;
    final currentRangeOk =
        task is! ParallelDownloadTask && partialBytes <= 0 ||
        current?.supportsRanges == true;
    if (current != null &&
        current.size != null &&
        currentSizeMatches &&
        currentRangeOk) {
      return (task: task, refreshed: false);
    }

    final refreshed = await _ref
        .read(downloadUrlRefresherProvider)
        .refresh(descriptor, currentUrl: task.url);
    if (refreshed == null) return (task: task, refreshed: false);
    final metadata = await getMetadata(
      refreshed.url,
      headers: refreshed.headers,
    );
    if (metadata?.size == null ||
        (expectedBytes > 0 && metadata!.size != expectedBytes) ||
        ((task is ParallelDownloadTask || partialBytes > 0) &&
            metadata?.supportsRanges != true)) {
      return (task: task, refreshed: false);
    }

    if (task is ParallelDownloadTask) {
      final replaced = await _parallel.replaceSource(
        task,
        url: refreshed.url,
        headers: refreshed.headers,
      );
      return replaced == null
          ? (task: task, refreshed: false)
          : (task: replaced, refreshed: true);
    }

    final updated = task.copyWith(
      url: refreshed.url,
      headers: Map<String, String>.from(refreshed.headers),
    );
    final record = await FileDownloader().database.recordForId(task.taskId);
    if (record != null) {
      await FileDownloader().database.updateRecord(
        TaskRecord(
          updated,
          record.status,
          record.progress,
          record.expectedFileSize,
        ),
      );
    }
    _nativeTransport.forget(task.taskId);
    return (task: updated, refreshed: true);
  }
"""
text = replace_one(text, old_range, new_range, 'range generation and refresh')
path.write_text(text)
print('download reliability integration applied')
