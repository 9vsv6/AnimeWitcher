from pathlib import Path


def replace_one(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    return text.replace(old, new, 1)

path = Path('lib/core/services/download_service.dart')
text = path.read_text()
old = """      final userPaused =
          isUserPausedMetadata(metadata) ||
          _userPausedIds.contains(task.taskId);

      if (userPaused) {"""
new = """      final userPaused =
          isUserPausedMetadata(metadata) ||
          _userPausedIds.contains(task.taskId);
      final recoveryPlan = planDownloadRecovery(
        persisted: record.status,
        queueWaiting: queueWaiting,
        userPaused: userPaused,
        stillInNativeQueue: stillNative,
        hasMetadata: metadata != null,
      );

      // Migrate pre-DownloadJobStore installs on first reconciliation. Only
      // byte-credible disk/manifests are counted; native resume blobs with no
      // visible prefix remain unknown instead of being guessed from percent.
      final saved = await _savedProgressFor(task);
      final expectedBytes = knownDownloadSize(<int?>[
        saved.totalSize,
        record.expectedFileSize,
        downloadMetadataExpectedBytes(metadata),
      ]);
      var durableBytes = saved.partialBytes;
      if (task is ParallelDownloadTask && expectedBytes > 0) {
        durableBytes = (progress * expectedBytes).floor();
      }
      final oldJob = await _jobStore.get(task.taskId);
      if (oldJob != null && oldJob.durableBytes > durableBytes) {
        durableBytes = oldJob.durableBytes;
      }
      final migratedJob = DownloadJobRecord(
        taskId: task.taskId,
        trackingUrl: trackingUrl,
        state: recoveryPlan.state,
        generation: oldJob?.generation ?? 0,
        durableBytes: durableBytes,
        expectedBytes: expectedBytes,
        userPaused: userPaused,
        queueWaiting: recoveryPlan.shouldRequeue,
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        fingerprint: oldJob?.fingerprint ??
            DownloadResourceFingerprint(
              expectedBytes: expectedBytes,
              finalUrl: task.url,
            ),
      );
      await _jobStore.put(migratedJob);

      if (userPaused) {"""
text = replace_one(text, old, new, 'startup durable job migration')
old2 = """      final shouldReenqueue = shouldRequeueInterruptedDownloadAfterRelaunch(
        persisted: record.status,
        queueWaiting: queueWaiting,
        userPaused: userPaused,
        stillInNativeQueue: stillNative,
        hasMetadata: metadata != null,
      );"""
new2 = """      final shouldReenqueue = recoveryPlan.shouldRequeue;"""
text = replace_one(text, old2, new2, 'central recovery plan routing')
path.write_text(text)
print('startup job migration applied')
