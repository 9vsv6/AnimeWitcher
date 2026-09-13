from pathlib import Path

path = Path('lib/features/library/presentation/downloads_provider.dart')
source = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count == 1:
        source = source.replace(old, new, 1)
        return
    if count == 0 and new in source:
        return
    raise SystemExit(f'{label} anchor mismatch: {count}')


replace_once(
    '''        if (status == TaskStatus.failed || status == TaskStatus.notFound) {\n          status = TaskStatus.paused;\n          if (progress < 0 || progress > 1) progress = 0.0;\n          unawaited(\n            FileDownloader().database.updateRecord(\n              TaskRecord(\n                record.task,\n                TaskStatus.paused,\n                progress,\n                record.expectedFileSize,\n              ),\n            ),\n          );\n        } else if (progress < 0 || progress > 1) {\n''',
    '''        if (status == TaskStatus.failed || status == TaskStatus.notFound) {\n          // Legacy executor state is presentation evidence only. Migration and\n          // repair belong to DownloadService reconciliation; never rewrite the\n          // plugin database while building a UI snapshot.\n          status = TaskStatus.paused;\n          if (progress < 0 || progress > 1) progress = 0.0;\n        } else if (progress < 0 || progress > 1) {\n''',
    'legacy lifecycle rewrite',
)

replace_once(
    '''    final collapsed = collapseDuplicateDownloads(items);\n    for (final extra in collapsed.extraCompleteRecords) {\n      await FileDownloader().database.deleteRecordWithId(extra.task.taskId);\n      await storage.removeDownloadMetadata(extra.task.taskId);\n      await deleteDownloadedEpisodeArtwork(extra.id);\n    }\n    return _orderDownloads(collapsed.visible);\n''',
    '''    final collapsed = collapseDuplicateDownloads(items);\n    // Duplicate repair is lifecycle reconciliation, not presentation cleanup.\n    // The UI collapses duplicate evidence without mutating executor/storage.\n    return _orderDownloads(collapsed.visible);\n''',
    'duplicate destructive cleanup',
)

replace_once(
    '''      ref.read(downloadChunkProgressProvider.notifier).remove(item.id);\n      // Artwork is presentation cache, not lifecycle authority. DM-12 will\n      // remove the remaining presentation-owned cache mutation separately.\n      try {\n        await deleteDownloadedEpisodeArtwork(item.id);\n      } catch (_) {}\n''',
    '''      ref.read(downloadChunkProgressProvider.notifier).remove(item.id);\n''',
    'delete artwork cleanup',
)

path.write_text(source)
