from pathlib import Path


def replace_one(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 match, found {count}')
    return text.replace(old, new, 1)

service_path = Path('lib/core/services/download_service.dart')
service = service_path.read_text()
service = replace_one(
    service,
    """      onFailure: (failure) async {
        if (!logical || token == null || !await _jobStore.accepts(token)) return;
        if (failure.action == DownloadFailureAction.refreshUrl) {""",
    """      onFailure: (failure) async {
        if (!logical || token == null) return;
        final activeToken = token;
        if (!await _jobStore.accepts(activeToken)) return;
        if (failure.action == DownloadFailureAction.refreshUrl) {""",
    'promote attempt token',
)
service = replace_one(
    service,
    """          await _jobStore.updateForAttempt(
            token,
            state: DownloadJobState.completed,""",
    """          await _jobStore.updateForAttempt(
            activeToken,
            state: DownloadJobState.completed,""",
    'use promoted token',
)
service_path.write_text(service)

parallel_path = Path('lib/core/services/persistent_parallel_download.dart')
parallel = parallel_path.read_text()
parallel = replace_one(
    parallel,
    """      final updated = task.copyWith(
        url: url,
        headers: Map<String, String>.from(headers),
      );
      if (updated is! ParallelDownloadTask) return null;
      session.task = updated;""",
    """      final updated = task.copyWith(
        url: url,
        headers: Map<String, String>.from(headers),
      );
      session.task = updated;""",
    'remove redundant parallel type check',
)
parallel_path.write_text(parallel)
print('analyze fixes applied')
