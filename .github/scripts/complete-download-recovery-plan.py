from pathlib import Path
import re


def read(path: str) -> str:
    return Path(path).read_text()


def write(path: str, text: str) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(text)


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match, found {count}: {old[:80]!r}")
    write(path, text.replace(old, new, 1))


def insert_before(path: str, anchor: str, addition: str) -> None:
    text = read(path)
    if addition.strip() in text:
        return
    count = text.count(anchor)
    if count != 1:
        raise SystemExit(f"{path}: insertion anchor count={count}: {anchor[:80]!r}")
    write(path, text.replace(anchor, addition + anchor, 1))


def replace_regex(path: str, pattern: str, replacement: str) -> None:
    text = read(path)
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"{path}: regex match count={count}: {pattern[:100]!r}")
    write(path, updated)


# ---------------------------------------------------------------------------
# #4/#15: centralize recovery byte authority and logical JobStore checkpoints.
# ---------------------------------------------------------------------------
insert_before(
    "lib/core/services/download_job_state.dart",
    "/// Identifies one concrete execution attempt of a logical episode.\n",
    r'''/// Source of the byte count selected during startup/resume reconciliation.
/// Percentages from plugin/UI metadata are deliberately absent: they can inform
/// presentation, but they are never durable byte evidence.
enum DownloadRecoveryByteSource {
  verifiedFinalFile,
  exactDisk,
  jobStore,
  multipartManifest,
  none,
}

class DownloadRecoveryByteSelection {
  const DownloadRecoveryByteSelection({
    required this.bytes,
    required this.source,
  });

  final int bytes;
  final DownloadRecoveryByteSource source;
}

/// Apply the recovery truth ordering used by the download manager.
///
/// A verified final file wins. Otherwise exact visible bytes win over logical
/// checkpoints. JobStore and the current multipart manifest are the final
/// durable fallbacks. Decimal progress is intentionally not accepted here.
DownloadRecoveryByteSelection selectDownloadRecoveryBytes({
  int verifiedFinalFileBytes = -1,
  int exactDiskBytes = -1,
  int currentGenerationJobBytes = -1,
  int multipartManifestBytes = -1,
}) {
  if (verifiedFinalFileBytes >= 0) {
    return DownloadRecoveryByteSelection(
      bytes: verifiedFinalFileBytes,
      source: DownloadRecoveryByteSource.verifiedFinalFile,
    );
  }
  if (exactDiskBytes >= 0) {
    return DownloadRecoveryByteSelection(
      bytes: exactDiskBytes,
      source: DownloadRecoveryByteSource.exactDisk,
    );
  }
  if (currentGenerationJobBytes >= 0) {
    return DownloadRecoveryByteSelection(
      bytes: currentGenerationJobBytes,
      source: DownloadRecoveryByteSource.jobStore,
    );
  }
  if (multipartManifestBytes >= 0) {
    return DownloadRecoveryByteSelection(
      bytes: multipartManifestBytes,
      source: DownloadRecoveryByteSource.multipartManifest,
    );
  }
  return const DownloadRecoveryByteSelection(
    bytes: 0,
    source: DownloadRecoveryByteSource.none,
  );
}

''',
)

insert_before(
    "lib/core/services/download_job_store.dart",
    "  /// Start a new execution generation atomically. The durable bytes and\n",
    r'''  /// Persist one logical lifecycle checkpoint while preserving the store's
  /// monotonic byte, generation and resource-identity invariants.
  ///
  /// DownloadService supplies orchestration evidence; this store owns how that
  /// evidence is merged with the durable logical record. This keeps lifecycle
  /// writes out of UI/plugin code and prevents a status-only checkpoint from
  /// discarding stronger identity or byte evidence.
  Future<bool> checkpoint({
    required String taskId,
    required String trackingUrl,
    required DownloadJobState state,
    int? durableBytes,
    int? expectedBytes,
    bool? userPaused,
    bool? queueWaiting,
    DownloadResourceFingerprint? fingerprint,
    int? updatedAtMillis,
  }) => _serialize(() async {
    final id = taskId.trim();
    final tracking = trackingUrl.trim();
    if (id.isEmpty || tracking.isEmpty) return false;

    final current = await get(id);
    final incomingBytes = durableBytes ?? current?.durableBytes ?? 0;
    if (incomingBytes < 0) return false;
    final keptBytes = current != null && current.durableBytes > incomingBytes
        ? current.durableBytes
        : incomingBytes;
    final incomingExpected = expectedBytes ?? -1;
    final keptExpected = incomingExpected > 0
        ? incomingExpected
        : (current?.expectedBytes ?? -1);
    final now = updatedAtMillis ?? DateTime.now().millisecondsSinceEpoch;

    final next = current == null
        ? DownloadJobRecord(
            taskId: id,
            trackingUrl: tracking,
            state: state,
            generation: 0,
            durableBytes: keptBytes,
            expectedBytes: keptExpected,
            userPaused: userPaused ?? false,
            queueWaiting: queueWaiting ?? false,
            updatedAtMillis: now,
            fingerprint: fingerprint,
          )
        : current.copyWith(
            state: state,
            durableBytes: keptBytes,
            expectedBytes: keptExpected,
            userPaused: userPaused ?? current.userPaused,
            queueWaiting: queueWaiting ?? current.queueWaiting,
            updatedAtMillis: now,
            fingerprint: fingerprint,
          );
    return _putUnlocked(next);
  });

''',
)

# ---------------------------------------------------------------------------
# #11: HostProfile is serialized history/seed only; Governor remains runtime.
# ---------------------------------------------------------------------------
replace_once(
    "lib/core/services/download_host_profile.dart",
    "  final DownloadHostProfileBackend backend;\n  final DateTime Function() _now;\n\n  Future<DownloadHostProfile?> getForUrl(String url) async {\n",
    r'''  final DownloadHostProfileBackend backend;
  final DateTime Function() _now;
  final Map<String, Future<void>> _writeChains = <String, Future<void>>{};

  /// Persisted host profiles are history/seed data only. Runtime connection
  /// decisions belong to DownloadConnectionGovernor. Serialize profile
  /// read-modify-write mutations by origin so an older async sample can never
  /// overwrite newer pressure knowledge after callbacks race each other.
  Future<T> _serializeOrigin<T>(
    String url,
    Future<T> Function() action,
  ) {
    final origin = downloadOriginKey(url);
    final previous = _writeChains[origin] ?? Future<void>.value();
    late final Future<void> barrier;
    final result = previous.catchError((_) {}).then((_) => action());
    barrier = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _writeChains[origin] = barrier;
    return result.whenComplete(() {
      if (identical(_writeChains[origin], barrier)) {
        _writeChains.remove(origin);
      }
    });
  }

  Future<DownloadHostProfile?> getForUrl(String url) async {
''',
)
replace_once(
    "lib/core/services/download_host_profile.dart",
    "  }) async {\n    final now = _now();\n    final origin = downloadOriginKey(url);\n    final previous = await getForUrl(url);\n    final connections = activeConnections\n",
    "  }) => _serializeOrigin(url, () async {\n    final now = _now();\n    final origin = downloadOriginKey(url);\n    final previous = await getForUrl(url);\n    final connections = activeConnections\n",
)
replace_once(
    "lib/core/services/download_host_profile.dart",
    "    await backend.write(origin, profile.toJson());\n    return profile;\n  }\n\n  Future<DownloadHostProfile> recordPressure({\n",
    "    await backend.write(origin, profile.toJson());\n    return profile;\n  });\n\n  Future<DownloadHostProfile> recordPressure({\n",
)
# The second method has the same `}) async {` shape; scope the replacement from
# its signature onward to avoid touching other methods.
replace_regex(
    "lib/core/services/download_host_profile.dart",
    r"(  Future<DownloadHostProfile> recordPressure\(\{\n    required String url,\n    required int fallbackCeiling,\n  \}\)) async \{",
    r"\1 => _serializeOrigin(url, () async {",
)
replace_once(
    "lib/core/services/download_host_profile.dart",
    "    await backend.write(origin, profile.toJson());\n    return profile;\n  }\n}\n\nint _asInt",
    "    await backend.write(origin, profile.toJson());\n    return profile;\n  });\n}\n\nint _asInt",
)

# ---------------------------------------------------------------------------
# #5: byte-for-byte source proof before multipart URL replacement.
# ---------------------------------------------------------------------------
insert_before(
    "lib/core/services/download_range_transfer.dart",
    "  Future<bool> stop(String id) async {\n",
    r'''  /// Verify a visible local prefix against a candidate source without
  /// appending bytes. Multipart URL refresh uses this before retaining old
  /// ranges. The returned validator may be pinned by the caller, but a matching
  /// byte prefix is sufficient when the origin exposes no validator.
  Future<({bool matches, String? validator})> verifyExistingPrefix({
    required String id,
    required String url,
    required Map<String, String> headers,
    required File file,
    required int written,
  }) async {
    if (written <= 0 || !await file.exists() || await file.length() < written) {
      return (matches: false, validator: null);
    }
    final operation = _RangeOperation(
      id: '$id.identity',
      canRefreshUrl: false,
    );
    try {
      final probe = await _probeSavedPrefix(
        operation: operation,
        url: url,
        headers: headers,
        spec: _RangeSpec.fromHeaders(headers),
        file: file,
        written: written,
      );
      return (matches: probe != null, validator: probe?.validator);
    } finally {
      operation.token.cancel('Identity probe complete');
    }
  }

''',
)

insert_before(
    "lib/core/services/download_parallel.dart",
    "bool isLogicalEpisodeDownloadTask(Task task) =>\n",
    r'''/// True when a multipart child was rebound to a refreshed source and must
/// not consume native resumeData that can still embed the previous URL.
bool downloadInternalSourceValidationRequired(Task task) {
  if (!isInternalDownloaderChunk(task)) return false;
  final raw = task.metaData.trim();
  if (raw.isEmpty) return false;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map && decoded['sourceValidationRequired'] == true;
  } catch (_) {
    return false;
  }
}

''',
)

replace_once(
    "lib/core/services/persistent_parallel_download.dart",
    "/// observed from a validated child response, so later/relaunched ranges\n/// cannot silently assemble bytes from a different resource generation.\nconst int kParallelManifestSchemaVersion = 3;\n",
    "/// observed from a validated child response, so later/relaunched ranges\n/// cannot silently assemble bytes from a different resource generation.\n/// Version 4 also persists whether a child must bypass old native resumeData\n/// after its parent source URL was refreshed.\nconst int kParallelManifestSchemaVersion = 4;\n",
)
replace_once(
    "lib/core/services/persistent_parallel_download.dart",
    "    this.shouldRecoverFailedStart,\n    this.onSourceRefreshNeeded,\n    this.recoveryDelay = const Duration(seconds: 1),\n",
    "    this.shouldRecoverFailedStart,\n    this.onSourceRefreshNeeded,\n    this.verifyPartSource,\n    this.recoveryDelay = const Duration(seconds: 1),\n",
)
replace_once(
    "lib/core/services/persistent_parallel_download.dart",
    "  final bool Function(String childTaskId)? shouldRecoverFailedStart;\n  final void Function(String parentTaskId)? onSourceRefreshNeeded;\n  final Duration recoveryDelay;\n",
    "  final bool Function(String childTaskId)? shouldRecoverFailedStart;\n  final void Function(String parentTaskId)? onSourceRefreshNeeded;\n  final Future<({bool matches, String? validator})> Function(\n    DownloadTask task,\n    File file,\n    int bytes,\n  )? verifyPartSource;\n  final Duration recoveryDelay;\n",
)
replace_once(
    "lib/core/services/persistent_parallel_download.dart",
    "    metadata['parentTaskId'] = session.task.taskId;\n    metadata['attemptGeneration'] = part.attemptGeneration;\n    return jsonEncode(metadata);\n",
    "    metadata['parentTaskId'] = session.task.taskId;\n    metadata['attemptGeneration'] = part.attemptGeneration;\n    metadata['sourceValidationRequired'] = part.sourceValidationRequired;\n    return jsonEncode(metadata);\n",
)
insert_before(
    "lib/core/services/persistent_parallel_download.dart",
    "  /// Replace only the remote source of a paused/restored multipart job.\n",
    r'''  /// Clear the one-shot source-refresh fence after the child has either
  /// opened a prefix-validated Range on the refreshed URL or restarted that
  /// immutable Range from byte zero.
  Future<bool> markPartSourceValidated(String childTaskId) async {
    if (_disposed) return false;
    final session = _children[childTaskId];
    if (session == null || session.deleted) return false;
    return session.serialize(() async {
      _DownloadPart? match;
      for (final part in session.parts) {
        if (part.task.taskId == childTaskId) {
          match = part;
          break;
        }
      }
      if (match == null) return false;
      if (!match.sourceValidationRequired) return true;
      match.sourceValidationRequired = false;
      _refreshPartAttemptMetadata(session, match);
      await _persist(session);
      return true;
    });
  }

''',
)
replace_regex(
    "lib/core/services/persistent_parallel_download.dart",
    r"  Future<ParallelDownloadTask\?> replaceSource\(\n    ParallelDownloadTask task, \{\n    required String url,\n    required Map<String, String> headers,\n  \}\) async \{.*?\n  \}\n\n  /// Includes native tasks",
    r'''  Future<ParallelDownloadTask?> replaceSource(
    ParallelDownloadTask task, {
    required String url,
    required Map<String, String> headers,
  }) async {
    if (_disposed || !await restore(task)) return null;
    final session = _sessions[task.taskId]!;
    _speedTelemetry.seed(
      task.taskId,
      transferredBytes: session.creditedBytes,
      expectedBytes: session.size,
    );
    return session.serialize(() async {
      if (_disposed || session.deleted || session.active) return null;

      // Before retaining any visible byte from the previous signed source,
      // prove that the refreshed URL serves the same resource. Validators are
      // checked when available; otherwise every visible part prefix is compared
      // byte-for-byte. Hidden native resumeData cannot be proven here and is
      // therefore fenced so _startPart will re-fetch that Range from byte zero.
      var refreshedValidator = session.resourceValidator;
      final verifier = verifyPartSource;
      for (final part in session.parts) {
        File? localFile;
        var localBytes = 0;
        try {
          final saved = await canonicalizePartialDownloadFile(
            destinationPath: await part.task.filePath(),
          );
          if (saved != null) {
            localFile = saved.file;
            localBytes = saved.bytes;
          } else {
            final candidate = File(await part.task.filePath());
            if (await candidate.exists()) {
              localFile = candidate;
              localBytes = await candidate.length();
            }
          }
        } catch (_) {}

        if (part.complete && localBytes != part.size) return null;
        if (localFile == null || localBytes <= 0) continue;
        if (verifier == null) return null;

        final probeHeaders = Map<String, String>.from(headers)
          ..removeWhere(
            (key, _) =>
                key.toLowerCase() == 'range' || key.toLowerCase() == 'if-range',
          );
        probeHeaders['Range'] = 'bytes=${part.from}-${part.to}';
        probeHeaders['Accept-Encoding'] = 'identity';
        final probeTask = part.task.copyWith(
          url: url,
          headers: probeHeaders,
        );
        final probe = await verifier(probeTask, localFile, localBytes);
        if (!probe.matches) return null;
        final observed = probe.validator;
        if (observed != null) {
          if (refreshedValidator != null && refreshedValidator != observed) {
            return null;
          }
          refreshedValidator = observed;
        }
      }

      final updated = task.copyWith(
        url: url,
        headers: Map<String, String>.from(headers),
      );
      session.task = updated;
      session.resourceValidator = refreshedValidator;
      for (final part in session.parts) {
        final childHeaders = Map<String, String>.from(headers)
          ..removeWhere(
            (key, _) =>
                key.toLowerCase() == 'range' || key.toLowerCase() == 'if-range',
          );
        childHeaders['Range'] = 'bytes=${part.from}-${part.to}';
        childHeaders['Accept-Encoding'] = 'identity';
        final validator = session.resourceValidator;
        if (validator != null) childHeaders['If-Range'] = validator;

        // Native resumeData can embed the old signed URL. Any unfinished child
        // with a saved prefix must switch through the validated Dart Range path
        // once before native resume is allowed again.
        part.sourceValidationRequired =
            !part.complete &&
            (part.progress > 0 || part.credibleProgress > 0);
        part.task = part.task.copyWith(
          url: url,
          headers: childHeaders,
          retries: kDownloadPartRetries,
        );
        _refreshPartAttemptMetadata(session, part);
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

  /// Includes native tasks''',
)
replace_once(
    "lib/core/services/persistent_parallel_download.dart",
    "    part.lastNativeBridgeBytes = 0;\n    part.lastNativeBridgeAt = null;\n",
    "    part.lastNativeBridgeBytes = 0;\n    part.lastNativeBridgeAt = null;\n    part.sourceValidationRequired = false;\n",
)
replace_once(
    "lib/core/services/persistent_parallel_download.dart",
    "    this.attemptGeneration = 0,\n    double? credibleProgress,\n",
    "    this.attemptGeneration = 0,\n    this.sourceValidationRequired = false,\n    double? credibleProgress,\n",
)
replace_once(
    "lib/core/services/persistent_parallel_download.dart",
    "  bool complete;\n  int attemptGeneration;\n  bool launched = false;\n",
    "  bool complete;\n  int attemptGeneration;\n  bool sourceValidationRequired;\n  bool launched = false;\n",
)
replace_once(
    "lib/core/services/persistent_parallel_download.dart",
    "      attemptGeneration: (json['attemptGeneration'] as num?)?.toInt() ?? 0,\n      credibleProgress: complete\n",
    "      attemptGeneration: (json['attemptGeneration'] as num?)?.toInt() ?? 0,\n      sourceValidationRequired: json['sourceValidationRequired'] == true,\n      credibleProgress: complete\n",
)
replace_once(
    "lib/core/services/persistent_parallel_download.dart",
    "    'complete': complete,\n    'attemptGeneration': attemptGeneration,\n  };\n",
    "    'complete': complete,\n    'attemptGeneration': attemptGeneration,\n    'sourceValidationRequired': sourceValidationRequired,\n  };\n",
)

# ---------------------------------------------------------------------------
# #1/#3/#4/#9/#15: startup preflight, tombstones, and JobStore ownership seam.
# ---------------------------------------------------------------------------
replace_once(
    "lib/core/services/download_service.dart",
    "  final Set<String> _refreshingParallelParentIds = <String>{};\n  final List<String> _sessionOrder = [];\n",
    "  final Set<String> _refreshingParallelParentIds = <String>{};\n  final Set<String> _terminalJobIds = <String>{};\n  final List<String> _sessionOrder = [];\n",
)
replace_once(
    "lib/core/services/download_service.dart",
    "      onSourceRefreshNeeded: _scheduleParallelParentRefresh,\n      onUpdate: (update) {\n",
    "      onSourceRefreshNeeded: _scheduleParallelParentRefresh,\n      verifyPartSource: (task, file, bytes) =>\n          _rangeTransfers.verifyExistingPrefix(\n            id: task.taskId,\n            url: task.url,\n            headers: task.headers,\n            file: file,\n            written: bytes,\n          ),\n      onUpdate: (update) {\n",
)
replace_once(
    "lib/core/services/download_service.dart",
    "    if (_userPausedIds.contains(taskId) ||\n        _cancellingUrls.contains(trackingUrl)) {\n",
    "    if (_userPausedIds.contains(taskId) ||\n        _terminalJobIds.contains(taskId) ||\n        _cancellingUrls.contains(trackingUrl)) {\n",
)
replace_once(
    "lib/core/services/download_service.dart",
    "    diagnosticLog.record('chunk.update', {\n",
    "    if (_terminalJobIds.contains(parentTaskId) ||\n        _userPausedIds.contains(parentTaskId)) {\n      return;\n    }\n    diagnosticLog.record('chunk.update', {\n",
)
replace_once(
    "lib/core/services/download_service.dart",
    "    _expectedSizePersistedIds.clear();\n    unawaited(_nativeTransport.dispose());\n",
    "    _expectedSizePersistedIds.clear();\n    _terminalJobIds.clear();\n    unawaited(_nativeTransport.dispose());\n",
)
replace_once(
    "lib/core/services/download_service.dart",
    "    diagnosticLog.record('service.initialize');\n    // 1. Configure the downloader (chainable API)\n",
    "    diagnosticLog.record('service.initialize');\n    // Restore durable user intent before native/plugin callbacks can race the\n    // startup reconciliation pass.\n    await _restoreAuthoritativeJobIntent();\n    // 1. Configure the downloader (chainable API)\n",
)
replace_once(
    "lib/core/services/download_service.dart",
    "      if (_parallel.handleUpdate(update)) return;\n      if (isInternalDownloaderChunk(update.task)) return;\n      final trackingUrl = update.task.metaData.isNotEmpty\n",
    "      if (_parallel.handleUpdate(update)) return;\n      if (isInternalDownloaderChunk(update.task)) return;\n      if (_terminalJobIds.contains(update.task.taskId)) return;\n      final trackingUrl = update.task.metaData.isNotEmpty\n",
)
insert_before(
    "lib/core/services/download_service.dart",
    "  /// Persist lifecycle boundaries for the logical episode without turning\n",
    r'''  Future<void> _restoreAuthoritativeJobIntent() async {
    for (final job in await _jobStore.all()) {
      final paused =
          job.userPaused ||
          job.state == DownloadJobState.pausing ||
          job.state == DownloadJobState.pausedByUser;
      final terminal =
          job.state == DownloadJobState.completed ||
          job.state == DownloadJobState.canceled ||
          job.state == DownloadJobState.orphaned;
      if (paused) _userPausedIds.add(job.taskId);
      if (job.queueWaiting || job.state == DownloadJobState.queued) {
        _queueWaitingIds.add(job.taskId);
      }
      if (terminal) _terminalJobIds.add(job.taskId);
    }
  }

''',
)
replace_regex(
    "lib/core/services/download_service.dart",
    r"  /// Persist lifecycle boundaries for the logical episode without turning\n  /// hot progress callbacks into Hive writes\. Durable bytes are monotonic and\n  /// identity evidence from an existing job is never discarded\.\n  Future<void> _checkpointLogicalJob\(.*?\n  \}\n\n  Future<void> _recoverPersistedDownloads",
    r'''  /// Persist lifecycle boundaries for the logical episode without turning
  /// hot progress callbacks into Hive writes. DownloadJobStore owns monotonic
  /// byte/identity merging; this service only supplies orchestration evidence.
  Future<void> _checkpointLogicalJob(
    DownloadTask task, {
    required DownloadJobState state,
    int? durableBytes,
    int? expectedBytes,
    bool? userPaused,
    bool? queueWaiting,
  }) async {
    final terminal =
        state == DownloadJobState.completed ||
        state == DownloadJobState.canceled ||
        state == DownloadJobState.orphaned;
    if (_terminalJobIds.contains(task.taskId) && !terminal) {
      diagnosticLog.record('job.checkpointRejected', {
        'taskId': task.taskId,
        'status': state.name,
        'reason': 'terminalTombstone',
      });
      return;
    }
    try {
      final accepted = await _jobStore.checkpoint(
        taskId: task.taskId,
        trackingUrl: downloadTrackingUrl(task),
        state: state,
        durableBytes: durableBytes,
        expectedBytes: expectedBytes,
        userPaused: userPaused,
        queueWaiting: queueWaiting,
        fingerprint: DownloadResourceFingerprint(
          expectedBytes: expectedBytes ?? -1,
          finalUrl: task.url,
        ),
      );
      if (!accepted) {
        diagnosticLog.record('job.checkpointRejected', {
          'taskId': task.taskId,
          'status': state.name,
        });
        return;
      }
      if (terminal) _terminalJobIds.add(task.taskId);
    } catch (error) {
      diagnosticLog.record('job.checkpointError', {
        'taskId': task.taskId,
        'status': state.name,
        'errorType': error.runtimeType.toString(),
      });
    }
  }

  Future<void> _recoverPersistedDownloads''',
)
replace_once(
    "lib/core/services/download_service.dart",
    "    try {\n      final job = await _jobStore.get(taskId);\n      if (job != null && job.expectedBytes <= 0) {\n        final derived = progress != null && progress > 0 && progress <= 1\n            ? (progress * expectedBytes).floor()\n            : 0;\n        final durable = derived > job.durableBytes ? derived : job.durableBytes;\n        await _jobStore.put(\n          job.copyWith(\n            expectedBytes: expectedBytes,\n            durableBytes: durable,\n            updatedAtMillis: DateTime.now().millisecondsSinceEpoch,\n          ),\n        );\n      }\n    } catch (_) {}\n",
    "    try {\n      final job = await _jobStore.get(taskId);\n      if (job != null && job.expectedBytes <= 0) {\n        await _jobStore.checkpoint(\n          taskId: job.taskId,\n          trackingUrl: job.trackingUrl,\n          state: job.state,\n          durableBytes: job.durableBytes,\n          expectedBytes: expectedBytes,\n          userPaused: job.userPaused,\n          queueWaiting: job.queueWaiting,\n          fingerprint: job.fingerprint,\n        );\n      }\n    } catch (_) {}\n",
)
replace_once(
    "lib/core/services/download_service.dart",
    "    var partialBytes = 0;\n    try {\n      final path = await task.filePath();\n      if (path.isNotEmpty) {\n        final partial = await findPartialDownloadFile(destinationPath: path);\n        if (partial != null) {\n          partialBytes = await partial.length();\n          if (parallelProgress == null && totalSize > 0 && partialBytes > 0) {\n            progress = keepLastKnownDownloadProgress(\n              incoming: progress,\n              lastKnown: partialBytes / totalSize,\n            );\n          }\n        }\n      }\n    } catch (_) {}\n    final credibleBytes = partialBytes > 0\n        ? partialBytes\n        : (totalSize > 0 && progress > 0 ? (totalSize * progress).floor() : 0);\n    _telemetry.seed(\n      task.taskId,\n      transferredBytes: credibleBytes,\n      expectedBytes: totalSize,\n    );\n",
    "    var partialBytes = 0;\n    var exactDiskBytes = -1;\n    try {\n      final path = await task.filePath();\n      if (path.isNotEmpty) {\n        final partial = await findPartialDownloadFile(destinationPath: path);\n        if (partial != null) {\n          partialBytes = await partial.length();\n          exactDiskBytes = partialBytes;\n          if (parallelProgress == null && totalSize > 0 && partialBytes > 0) {\n            progress = keepLastKnownDownloadProgress(\n              incoming: progress,\n              lastKnown: partialBytes / totalSize,\n            );\n          }\n        }\n      }\n    } catch (_) {}\n    final manifestBytes =\n        task is ParallelDownloadTask && parallelProgress != null && totalSize > 0\n        ? (parallelProgress * totalSize).floor()\n        : -1;\n    final recoveryBytes = selectDownloadRecoveryBytes(\n      exactDiskBytes: exactDiskBytes,\n      currentGenerationJobBytes: job?.durableBytes ?? -1,\n      multipartManifestBytes: manifestBytes,\n    );\n    _telemetry.seed(\n      task.taskId,\n      transferredBytes: recoveryBytes.bytes,\n      expectedBytes: totalSize,\n    );\n",
)
replace_once(
    "lib/core/services/download_service.dart",
    "      var durableBytes = saved.partialBytes;\n      if (task is ParallelDownloadTask && expectedBytes > 0) {\n        durableBytes = (progress * expectedBytes).floor();\n      }\n      if (oldJob != null && oldJob.durableBytes > durableBytes) {\n        durableBytes = oldJob.durableBytes;\n      }\n",
    "      final manifestBytes = task is ParallelDownloadTask && expectedBytes > 0\n          ? (progress * expectedBytes).floor()\n          : -1;\n      final recoveryBytes = selectDownloadRecoveryBytes(\n        exactDiskBytes: saved.partialBytes > 0 ? saved.partialBytes : -1,\n        currentGenerationJobBytes: oldJob?.durableBytes ?? -1,\n        multipartManifestBytes: manifestBytes,\n      );\n      final durableBytes = recoveryBytes.bytes;\n",
)
replace_once(
    "lib/core/services/download_service.dart",
    "  }) async {\n    final transfer = _nativeTransport.handleFor(taskId);\n",
    "  }) async {\n    if (_terminalJobIds.contains(taskId)) return null;\n    final transfer = _nativeTransport.handleFor(taskId);\n",
)
replace_once(
    "lib/core/services/download_service.dart",
    "    _cancellingUrls.add(trackingUrl);\n    _queueWaitingIds.remove(taskId);\n",
    "    _cancellingUrls.add(trackingUrl);\n    _terminalJobIds.add(taskId);\n    _queueWaitingIds.remove(taskId);\n",
)
replace_regex(
    "lib/core/services/download_service.dart",
    r"  Future<bool> _startPart\(DownloadTask task, double progress, int size\) async \{.*?\n  \}\n\n  Future<bool> _enqueueTransfer",
    r'''  Future<bool> _startPart(DownloadTask task, double progress, int size) async {
    diagnosticLog.record('part.start', {
      'taskId': task.taskId,
      'progress': progress,
      'total': size,
    });
    if (_rangeTransfers.isActive(task.taskId)) return true;
    if ((await _liveTransferTasks()).any((live) => live.taskId == task.taskId)) {
      return true;
    }

    final forceSourceValidation =
        downloadInternalSourceValidationRequired(task);
    var nativeCanResume = false;
    if (!forceSourceValidation) {
      try {
        nativeCanResume = await FileDownloader()
            .taskCanResume(task)
            .timeout(const Duration(seconds: 3));
        if (nativeCanResume && await FileDownloader().resume(task)) return true;
      } catch (_) {
        // A stale native checkpoint must not prevent the disk-prefix fallback.
      }
    }

    final partial = await canonicalizePartialDownloadFile(
      destinationPath: await task.filePath(),
    );
    final bytes = partial?.bytes ?? 0;
    if (bytes == size && size > 0) {
      await FileDownloader().database.updateRecord(
        TaskRecord(task, TaskStatus.complete, 1, size),
      );
      if (forceSourceValidation) {
        await _parallel.markPartSourceValidated(task.taskId);
      }
      _sharedEvents.add(TaskStatusUpdate(task, TaskStatus.complete));
      return true;
    }
    if (bytes > 0 && bytes < size) {
      final started = await _appendRemainingWithDio(
        task,
        dest: partial!.file,
        existingBytes: bytes,
        expectedBytes: size,
      );
      if (started && forceSourceValidation) {
        await _parallel.markPartSourceValidated(task.taskId);
      }
      return started;
    }

    if (progress > 0 && bytes == 0 &&
        (!nativeCanResume || forceSourceValidation)) {
      // Resume bytes that exist only inside old native resumeData cannot be
      // proven after a signed URL refresh. Drop only this immutable Range's
      // phantom prefix and fetch it from byte zero on the refreshed source.
      final repaired = _parallel.resetUndurablePartProgress(
        task.taskId,
        durableBytes: 0,
      );
      if (!repaired) return false;
      diagnosticLog.record('part.checkpointLost', {
        'taskId': task.taskId,
        'progress': progress,
        'total': size,
        'sourceRefresh': forceSourceValidation,
      });
      await FileDownloader().database.updateRecord(
        TaskRecord(task, TaskStatus.paused, 0, size),
      );
      final enqueued = await FileDownloader().enqueue(task);
      if (enqueued && forceSourceValidation) {
        await _parallel.markPartSourceValidated(task.taskId);
      }
      return enqueued;
    }

    if (bytes > 0) return false;
    final enqueued = await FileDownloader().enqueue(task);
    if (enqueued && forceSourceValidation) {
      await _parallel.markPartSourceValidated(task.taskId);
    }
    return enqueued;
  }

  Future<bool> _enqueueTransfer''',
)

# ---------------------------------------------------------------------------
# #8: unknown-Content-Length single-transfer recovery matrix.
# ---------------------------------------------------------------------------
write(
    "test/core/services/download_unknown_size_recovery_test.dart",
    r'''import 'dart:async';
import 'dart:io';

import 'package:animewitcher/core/services/download_range_transfer.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory directory;
  late File file;
  late Dio dio;
  late String url;
  var rangeCapable = true;
  var slowFirstBody = false;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aw-unknown-size-');
    file = File('${directory.path}/episode.part');
    await file.writeAsBytes(<int>[]);
    dio = Dio();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://${server.address.host}:${server.port}/episode';
    rangeCapable = true;
    slowFirstBody = false;

    unawaited(() async {
      await for (final request in server) {
        try {
          final range = request.headers.value(HttpHeaders.rangeHeader);
          if (!rangeCapable || range == null) {
            request.response.statusCode = HttpStatus.ok;
            request.response.add(List<int>.generate(10, (i) => i));
            await request.response.close();
            continue;
          }
          final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range)!;
          final start = int.parse(match[1]!);
          final requestedEnd = match[2]!.isEmpty ? 9 : int.parse(match[2]!);
          final end = requestedEnd.clamp(start, 9);
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/10',
          );
          request.response.headers.set(HttpHeaders.etagHeader, '"unknown-v1"');
          // Intentionally do not set Content-Length: HttpServer will stream the
          // body chunked while Content-Range discovers the resource total.
          if (slowFirstBody && start == 0 && end == 9) {
            request.response.add(<int>[0, 1, 2, 3]);
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 250));
            request.response.add(<int>[4, 5, 6, 7, 8, 9]);
          } else {
            request.response.add(
              List<int>.generate(end - start + 1, (i) => start + i),
            );
          }
          await request.response.close();
        } catch (_) {
          try {
            await request.response.close();
          } catch (_) {}
        }
      }
    }());
  });

  tearDown(() async {
    dio.close(force: true);
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('unknown total resumes from a verified prefix and discovers total', () async {
    await file.writeAsBytes(<int>[0, 1, 2]);
    final runner = DownloadRangeTransfer(dio);
    final complete = Completer<(int, int)>();

    expect(
      await runner.start(
        id: 'episode',
        url: url,
        headers: const {},
        file: file,
        existingBytes: 3,
        expectedBytes: -1,
        onState: (written, total, done) async {
          if (done && !complete.isCompleted) complete.complete((written, total));
        },
        onPaused: (_, _) async {},
      ),
      isTrue,
    );

    expect(await complete.future.timeout(const Duration(seconds: 5)), (10, 10));
    expect(await file.readAsBytes(), List<int>.generate(10, (i) => i));
  });

  test('ignored Range never appends an unverified unknown-size prefix', () async {
    await file.writeAsBytes(<int>[0, 1, 2]);
    rangeCapable = false;
    final runner = DownloadRangeTransfer(dio);

    expect(
      await runner.start(
        id: 'episode',
        url: url,
        headers: const {},
        file: file,
        existingBytes: 3,
        expectedBytes: -1,
        onState: (_, _, _) async {},
        onPaused: (_, _) async {},
      ),
      isFalse,
    );
    expect(await file.readAsBytes(), <int>[0, 1, 2]);
  });

  test('same prefix can recover later when the origin starts honoring Range', () async {
    await file.writeAsBytes(<int>[0, 1, 2]);
    final runner = DownloadRangeTransfer(dio);
    rangeCapable = false;
    expect(
      await runner.start(
        id: 'episode',
        url: url,
        headers: const {},
        file: file,
        existingBytes: 3,
        expectedBytes: -1,
        onState: (_, _, _) async {},
        onPaused: (_, _) async {},
      ),
      isFalse,
    );

    rangeCapable = true;
    final complete = Completer<void>();
    expect(
      await runner.start(
        id: 'episode',
        url: url,
        headers: const {},
        file: file,
        existingBytes: 3,
        expectedBytes: -1,
        onState: (_, _, done) async {
          if (done && !complete.isCompleted) complete.complete();
        },
        onPaused: (_, _) async {},
      ),
      isTrue,
    );
    await complete.future.timeout(const Duration(seconds: 5));
    expect(await file.readAsBytes(), List<int>.generate(10, (i) => i));
  });

  test('process-style stop keeps bytes and a new runner safely resumes them', () async {
    slowFirstBody = true;
    final first = DownloadRangeTransfer(dio);
    final paused = Completer<int>();
    expect(
      await first.start(
        id: 'episode',
        url: url,
        headers: const {},
        file: file,
        existingBytes: 0,
        expectedBytes: -1,
        onState: (_, _, _) async {},
        onPaused: (written, _) async {
          if (!paused.isCompleted) paused.complete(written);
        },
      ),
      isTrue,
    );

    for (var i = 0; i < 100 && await file.length() < 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(await first.stop('episode'), isTrue);
    final durable = await paused.future.timeout(const Duration(seconds: 5));
    expect(durable, greaterThanOrEqualTo(4));
    expect(await file.length(), durable);

    slowFirstBody = false;
    final second = DownloadRangeTransfer(dio);
    final complete = Completer<void>();
    expect(
      await second.start(
        id: 'episode',
        url: url,
        headers: const {},
        file: file,
        existingBytes: durable,
        expectedBytes: -1,
        onState: (_, _, done) async {
          if (done && !complete.isCompleted) complete.complete();
        },
        onPaused: (_, _) async {},
      ),
      isTrue,
    );
    await complete.future.timeout(const Duration(seconds: 5));
    expect(await file.readAsBytes(), List<int>.generate(10, (i) => i));
  });
}
''',
)

# ---------------------------------------------------------------------------
# #9/#4: startup/native ownership and recovery truth matrix.
# ---------------------------------------------------------------------------
write(
    "test/core/services/download_startup_reconciliation_matrix_test.dart",
    r'''import 'package:animewitcher/core/services/download_job_state.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('startup ownership reconciliation matrix', () {
    test('native ownership beats stale failed plugin status', () {
      final plan = planDownloadRecoveryWithJobAuthority(
        persisted: TaskStatus.failed,
        queueWaiting: false,
        userPaused: false,
        stillInNativeQueue: true,
        hasMetadata: true,
        authoritativeState: DownloadJobState.running,
      );
      expect(plan.action, DownloadRecoveryAction.keepNative);
      expect(plan.state, DownloadJobState.running);
    });

    test('running DB row without a native owner becomes interrupted', () {
      final plan = planDownloadRecoveryWithJobAuthority(
        persisted: TaskStatus.running,
        queueWaiting: false,
        userPaused: false,
        stillInNativeQueue: false,
        hasMetadata: true,
        authoritativeState: DownloadJobState.running,
      );
      expect(plan.action, DownloadRecoveryAction.requeue);
      expect(plan.state, DownloadJobState.interrupted);
    });

    test('durable user pause beats a still-live native worker', () {
      final plan = planDownloadRecoveryWithJobAuthority(
        persisted: TaskStatus.running,
        queueWaiting: false,
        userPaused: false,
        stillInNativeQueue: true,
        hasMetadata: true,
        authoritativeState: DownloadJobState.pausedByUser,
        authoritativeUserPaused: true,
      );
      expect(plan.action, DownloadRecoveryAction.keepPaused);
      expect(plan.state, DownloadJobState.pausedByUser);
    });

    test('durable FIFO waiter survives stale plugin pause state', () {
      final plan = planDownloadRecoveryWithJobAuthority(
        persisted: TaskStatus.paused,
        queueWaiting: false,
        userPaused: false,
        stillInNativeQueue: false,
        hasMetadata: true,
        authoritativeState: DownloadJobState.queued,
        authoritativeQueueWaiting: true,
      );
      expect(plan.action, DownloadRecoveryAction.requeue);
      expect(plan.state, DownloadJobState.queued);
    });

    test('terminal logical state cannot be resurrected by native ownership', () {
      for (final state in <DownloadJobState>[
        DownloadJobState.completed,
        DownloadJobState.canceled,
        DownloadJobState.orphaned,
      ]) {
        final plan = planDownloadRecoveryWithJobAuthority(
          persisted: TaskStatus.running,
          queueWaiting: false,
          userPaused: false,
          stillInNativeQueue: true,
          hasMetadata: true,
          authoritativeState: state,
        );
        expect(plan.action, DownloadRecoveryAction.ignore, reason: '$state');
        expect(plan.state, state);
      }
    });
  });

  group('durable byte truth ordering', () {
    test('verified final file has highest authority', () {
      final selected = selectDownloadRecoveryBytes(
        verifiedFinalFileBytes: 100,
        exactDiskBytes: 80,
        currentGenerationJobBytes: 70,
        multipartManifestBytes: 60,
      );
      expect(selected.bytes, 100);
      expect(selected.source, DownloadRecoveryByteSource.verifiedFinalFile);
    });

    test('exact visible bytes beat logical snapshots', () {
      final selected = selectDownloadRecoveryBytes(
        exactDiskBytes: 80,
        currentGenerationJobBytes: 90,
        multipartManifestBytes: 95,
      );
      expect(selected.bytes, 80);
      expect(selected.source, DownloadRecoveryByteSource.exactDisk);
    });

    test('JobStore is used when exact bytes are not visible', () {
      final selected = selectDownloadRecoveryBytes(
        currentGenerationJobBytes: 70,
        multipartManifestBytes: 60,
      );
      expect(selected.bytes, 70);
      expect(selected.source, DownloadRecoveryByteSource.jobStore);
    });

    test('decimal plugin progress is not a recovery byte input', () {
      final selected = selectDownloadRecoveryBytes();
      expect(selected.bytes, 0);
      expect(selected.source, DownloadRecoveryByteSource.none);
    });
  });
}
''',
)

# ---------------------------------------------------------------------------
# #11: persisted host updates cannot race and overwrite newer runtime history.
# ---------------------------------------------------------------------------
write(
    "test/core/services/download_host_profile_race_test.dart",
    r'''import 'dart:async';

import 'package:animewitcher/core/services/download_host_profile.dart';
import 'package:flutter_test/flutter_test.dart';

class _GateBackend implements DownloadHostProfileBackend {
  final values = <String, Map<String, dynamic>>{};
  final firstWriteEntered = Completer<void>();
  final releaseFirstWrite = Completer<void>();
  var writes = 0;

  @override
  Future<void> delete(String origin) async => values.remove(origin);

  @override
  Future<Map<String, dynamic>?> read(String origin) async {
    final value = values[origin];
    return value == null ? null : Map<String, dynamic>.from(value);
  }

  @override
  Future<List<Map<String, dynamic>>> readAll() async => values.values
      .map((value) => Map<String, dynamic>.from(value))
      .toList(growable: false);

  @override
  Future<void> write(String origin, Map<String, Object> value) async {
    writes++;
    if (writes == 1) {
      if (!firstWriteEntered.isCompleted) firstWriteEntered.complete();
      await releaseFirstWrite.future;
    }
    values[origin] = Map<String, dynamic>.from(value);
  }
}

void main() {
  test('newer host pressure cannot be overwritten by an older async sample', () async {
    final backend = _GateBackend();
    final store = DownloadHostProfileStore(backend);
    final success = store.recordSuccess(
      url: 'https://cdn.test/a.mp4',
      activeConnections: 8,
      bytesPerSecond: 20 * 1024 * 1024,
    );
    await backend.firstWriteEntered.future.timeout(const Duration(seconds: 2));

    final pressure = store.recordPressure(
      url: 'https://cdn.test/b.mp4',
      fallbackCeiling: 2,
    );
    backend.releaseFirstWrite.complete();
    await Future.wait(<Future<Object>>[success, pressure]);

    final profile = await store.getForUrl('https://cdn.test/c.mp4');
    expect(profile, isNotNull);
    expect(profile!.safeConnectionCeiling, 2);
    expect(profile.consecutivePressure, 1);
  });
}
''',
)

# ---------------------------------------------------------------------------
# #5/#15: refreshed-source proof plus ownership-boundary regression checks.
# ---------------------------------------------------------------------------
write(
    "test/core/services/download_source_refresh_integrity_test.dart",
    r'''import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:animewitcher/core/services/download_parallel.dart';
import 'package:animewitcher/core/services/download_range_transfer.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('source identity probe accepts matching prefix and exposes validator', () async {
    final directory = await Directory.systemTemp.createTemp('aw-source-proof-');
    final file = File('${directory.path}/part');
    await file.writeAsBytes(<int>[0, 1, 2, 3]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dio = Dio();
    final url = 'http://${server.address.host}:${server.port}/episode';
    unawaited(() async {
      await for (final request in server) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 20-23/100',
        );
        request.response.headers.set(HttpHeaders.etagHeader, '"same-v2"');
        request.response.add(<int>[0, 1, 2, 3]);
        await request.response.close();
      }
    }());

    try {
      final runner = DownloadRangeTransfer(dio);
      final result = await runner.verifyExistingPrefix(
        id: 'part-1',
        url: url,
        headers: const {'Range': 'bytes=20-39'},
        file: file,
        written: 4,
      );
      expect(result.matches, isTrue);
      expect(result.validator, '"same-v2"');
    } finally {
      dio.close(force: true);
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });

  test('source identity probe rejects changed bytes before append', () async {
    final directory = await Directory.systemTemp.createTemp('aw-source-proof-');
    final file = File('${directory.path}/part');
    await file.writeAsBytes(<int>[0, 1, 2, 3]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dio = Dio();
    final url = 'http://${server.address.host}:${server.port}/episode';
    unawaited(() async {
      await for (final request in server) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 20-23/100',
        );
        request.response.add(<int>[9, 9, 9, 9]);
        await request.response.close();
      }
    }());

    try {
      final runner = DownloadRangeTransfer(dio);
      final result = await runner.verifyExistingPrefix(
        id: 'part-1',
        url: url,
        headers: const {'Range': 'bytes=20-39'},
        file: file,
        written: 4,
      );
      expect(result.matches, isFalse);
      expect(await file.readAsBytes(), <int>[0, 1, 2, 3]);
    } finally {
      dio.close(force: true);
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });

  test('refreshed multipart child metadata explicitly fences old resumeData', () {
    final task = DownloadTask(
      url: 'https://cdn.test/new',
      group: kPersistentDownloadChunkGroup,
      metaData: jsonEncode(<String, Object>{
        'parentTaskId': 'parent',
        'sourceValidationRequired': true,
      }),
    );
    expect(downloadInternalParentTaskId(task), 'parent');
    expect(downloadInternalSourceValidationRequired(task), isTrue);
  });

  test('DownloadService delegates logical merge policy to DownloadJobStore', () {
    final service = File('lib/core/services/download_service.dart').readAsStringSync();
    final start = service.indexOf('Future<void> _checkpointLogicalJob(');
    final end = service.indexOf('Future<void> _recoverPersistedDownloads', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final section = service.substring(start, end);
    expect(section, contains('_jobStore.checkpoint('));
    expect(section, isNot(contains('DownloadJobRecord(')));

    final parallel = File(
      'lib/core/services/persistent_parallel_download.dart',
    ).readAsStringSync();
    expect(parallel, contains('verifyPartSource'));
    expect(parallel, contains('sourceValidationRequired'));
  });
}
''',
)

# ---------------------------------------------------------------------------
# #14: deterministic fault-injection matrix for durable logical state.
# ---------------------------------------------------------------------------
write(
    "test/core/services/download_recovery_fault_injection_test.dart",
    r'''import 'dart:async';

import 'package:animewitcher/core/services/download_job_state.dart';
import 'package:animewitcher/core/services/download_job_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _FaultBackend implements DownloadJobBackend {
  final values = <String, Map<String, dynamic>>{};
  var failNextWrite = false;
  Completer<void>? blockNextWrite;

  @override
  Future<void> delete(String taskId) async => values.remove(taskId);

  @override
  Future<Map<String, dynamic>?> read(String taskId) async {
    final value = values[taskId];
    return value == null ? null : Map<String, dynamic>.from(value);
  }

  @override
  Future<List<Map<String, dynamic>>> readAll() async => values.values
      .map((value) => Map<String, dynamic>.from(value))
      .toList(growable: false);

  @override
  Future<void> write(String taskId, Map<String, Object?> value) async {
    final blocker = blockNextWrite;
    blockNextWrite = null;
    if (blocker != null) await blocker.future;
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('injected storage failure');
    }
    values[taskId] = Map<String, dynamic>.from(value);
  }
}

DownloadResourceFingerprint get fingerprint => const DownloadResourceFingerprint(
  strongEtag: '"ep-v1"',
  expectedBytes: 100,
);

Future<bool> checkpoint(
  DownloadJobStore store, {
  DownloadJobState state = DownloadJobState.running,
  int bytes = 0,
}) => store.checkpoint(
  taskId: 'ep',
  trackingUrl: 'tracking://ep',
  state: state,
  durableBytes: bytes,
  expectedBytes: 100,
  userPaused: state == DownloadJobState.pausedByUser,
  queueWaiting: state == DownloadJobState.queued,
  fingerprint: fingerprint,
);

void main() {
  test('write failure does not poison the serialized checkpoint chain', () async {
    final backend = _FaultBackend()..failNextWrite = true;
    final store = DownloadJobStore(backend);
    await expectLater(checkpoint(store, bytes: 10), throwsStateError);
    expect(await checkpoint(store, bytes: 12), isTrue);
    expect((await store.get('ep'))?.durableBytes, 12);
  });

  test('concurrent lifecycle writes are applied in invocation order', () async {
    final backend = _FaultBackend();
    final store = DownloadJobStore(backend);
    expect(await checkpoint(store, bytes: 10), isTrue);

    final gate = Completer<void>();
    backend.blockNextWrite = gate;
    final first = checkpoint(store, state: DownloadJobState.running, bytes: 20);
    await Future<void>.delayed(Duration.zero);
    final second = checkpoint(
      store,
      state: DownloadJobState.pausedByUser,
      bytes: 25,
    );
    gate.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    final job = await store.get('ep');
    expect(job?.durableBytes, 25);
    expect(job?.state, DownloadJobState.pausedByUser);
    expect(job?.userPaused, isTrue);
  });

  test('pause racing completion cannot regress a completed job', () async {
    final backend = _FaultBackend();
    final store = DownloadJobStore(backend);
    expect(await checkpoint(store, bytes: 90), isTrue);
    expect(
      await checkpoint(store, state: DownloadJobState.completed, bytes: 100),
      isTrue,
    );
    expect(
      await checkpoint(store, state: DownloadJobState.pausedByUser, bytes: 100),
      isFalse,
    );
    expect((await store.get('ep'))?.state, DownloadJobState.completed);
  });

  test('late callback from pre-relaunch generation is rejected', () async {
    final backend = _FaultBackend();
    final firstProcess = DownloadJobStore(backend);
    expect(await checkpoint(firstProcess, bytes: 40), isTrue);
    final old = await firstProcess.beginAttempt('ep');
    expect(old, isNotNull);
    expect(
      await firstProcess.updateForAttempt(old!, durableBytes: 55),
      isTrue,
    );

    final relaunched = DownloadJobStore(backend);
    final current = await relaunched.beginAttempt('ep');
    expect(current, isNotNull);
    expect(
      await relaunched.updateForAttempt(old, durableBytes: 80),
      isFalse,
    );
    expect((await relaunched.get('ep'))?.durableBytes, 55);
  });

  test('delete boundary invalidates old attempts and permits a true zero reset', () async {
    final backend = _FaultBackend();
    final store = DownloadJobStore(backend);
    expect(await checkpoint(store, bytes: 75), isTrue);
    final old = await store.beginAttempt('ep');
    expect(old, isNotNull);
    await store.remove('ep');
    expect(await store.accepts(old!), isFalse);
    expect(await checkpoint(store, bytes: 0), isTrue);
    expect((await store.get('ep'))?.durableBytes, 0);
  });
}
''',
)

print('Applied completion patch for all 15 download-recovery plan items.')
