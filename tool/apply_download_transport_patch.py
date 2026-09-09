from pathlib import Path

path = Path('lib/core/services/download_service.dart')
text = path.read_text()


def replace_one(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    text = text.replace(old, new, 1)


replace_one(
    "import 'download_range_transfer.dart';\nimport 'download_continued_processing_service.dart';",
    "import 'download_range_transfer.dart';\nimport 'download_transport.dart';\nimport 'download_continued_processing_service.dart';",
    'transport import',
)

replace_one(
    "  late final PersistentParallelDownload _parallel;\n  late final DownloadRangeTransfer _rangeTransfers;",
    "  late final PersistentParallelDownload _parallel;\n  late final DownloadRangeTransfer _rangeTransfers;\n  late final NativeSingleDownloadTransport _nativeTransport;",
    'transport field',
)

replace_one(
    "  DownloadService(this._ref) : _dio = _ref.read(dioClientProvider) {\n    _rangeTransfers = DownloadRangeTransfer(_dio);",
    "  DownloadService(this._ref) : _dio = _ref.read(dioClientProvider) {\n    _nativeTransport = NativeSingleDownloadTransport();\n    _rangeTransfers = DownloadRangeTransfer(_dio);",
    'transport constructor',
)

replace_one(
    "    unawaited(_parallel.dispose());\n    _rangeTransfers.dispose();\n    _updatesSubscription?.cancel();",
    "    unawaited(_parallel.dispose());\n    _rangeTransfers.dispose();\n    unawaited(_nativeTransport.dispose());\n    _updatesSubscription?.cancel();",
    'transport dispose',
)

replace_one(
    "    await FileDownloader().start(\n      doRescheduleKilledTasks: false,\n      markDownloadedComplete: false,\n    );\n\n    // 6. Restore UI rows",
    "    await FileDownloader().start(\n      doRescheduleKilledTasks: false,\n      markDownloadedComplete: false,\n    );\n    // Rebuild Transfer handles from the plugin database without enqueueing\n    // anything. Recovery below remains the only code allowed to decide whether\n    // an interrupted task should resume, wait, or stay user-paused.\n    await _nativeTransport.rehydrate(group: kLogicalDownloadGroup);\n\n    // 6. Restore UI rows",
    'rehydrate before recovery',
)

replace_one(
    "  }) async {\n    final track = trackingUrl ?? '';\n    for (final task in await _liveTransferTasks()) {",
    "  }) async {\n    final transfer = _nativeTransport.handleFor(taskId);\n    final transferTask = transfer?.task;\n    if (transfer != null &&\n        transferTask is DownloadTask &&\n        isLogicalEpisodeDownloadTask(transferTask) &&\n        isLiveNativeDownloadStatus(transfer.status)) {\n      return transferTask;\n    }\n    final track = trackingUrl ?? '';\n    for (final task in await _liveTransferTasks()) {",
    'live transfer handle',
)

replace_one(
    "        if (await FileDownloader().pause(task)) {\n          // pause() only acknowledges the command; native resume data arrives",
    "        if (await _nativeTransport.pause(task)) {\n          // pause() only acknowledges the command; native resume data arrives",
    'normal pause transport',
)

replace_one(
    "    final didPause = await FileDownloader().pause(downloadTask);",
    "    final didPause = downloadTask is ParallelDownloadTask\n        ? await FileDownloader().pause(downloadTask)\n        : await _nativeTransport.pause(downloadTask);",
    'system pause transport',
)

replace_one(
    "      resume: () => FileDownloader().resume(task),",
    "      resume: () => _nativeTransport.resume(task),",
    'strict resume transport',
)

replace_one(
    "  Future<bool> _enqueueTransfer(DownloadTask task, int totalBytes) async {\n    if (task is! ParallelDownloadTask) return FileDownloader().enqueue(task);",
    "  Future<bool> _enqueueTransfer(DownloadTask task, int totalBytes) async {\n    if (task is! ParallelDownloadTask) return _nativeTransport.start(task);",
    'fresh start transport',
)

replace_one(
    "        metaData: trackingUrl ?? url,\n      );",
    "        metaData: trackingUrl ?? url,\n        transferHints: animeDownloadTransferHints(expectedBytes: totalBytes),\n        stallTimeout: const Duration(seconds: 45),\n      );",
    'native transfer hints',
)

replace_one(
    "        if (parentRecord?.task is ParallelDownloadTask) {\n          await _parallel.cancel(parentRecord!.task as ParallelDownloadTask);\n        }\n        await FileDownloader().cancelTasksWithIds(ids.toList());",
    "        if (parentRecord?.task is ParallelDownloadTask) {\n          await _parallel.cancel(parentRecord!.task as ParallelDownloadTask);\n        } else if (parentRecord?.task is DownloadTask &&\n            isNativeSingleDownloadTask(parentRecord!.task)) {\n          await _nativeTransport.cancel(parentRecord.task as DownloadTask);\n          ids.remove(taskId);\n        }\n        if (ids.isNotEmpty) {\n          await FileDownloader().cancelTasksWithIds(ids.toList());\n        }\n        _nativeTransport.forget(taskId);",
    'manual cancel transport',
)

path.write_text(text)
print('download_service.dart transport integration applied')
