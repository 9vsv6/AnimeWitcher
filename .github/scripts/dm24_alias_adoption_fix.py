from pathlib import Path

path = Path('lib/core/services/download_service.dart')
source = path.read_text()

start_sig = 'Future<DownloadCommandOutcome> startDownloadOutcome({'
complete_sig = 'Future<List<TaskRecord>> _completeRecordsForEpisode('
drop_sig = 'Future<void> _dropCompleteRecords('

start = source.find(start_sig)
if start < 0:
    raise SystemExit('startDownloadOutcome missing')
complete = source.find(complete_sig, start)
if complete < 0:
    raise SystemExit('_completeRecordsForEpisode missing')

start_body = source[start:complete]

old_identity = '''    final logicalId = DownloadLogicalIdentity.fromMedia(
      item: item,
      episode: episode,
    ).key;
'''
new_identity = '''    final logicalIdentity = DownloadLogicalIdentity.fromMedia(
      item: item,
      episode: episode,
    );
    final logicalId = logicalIdentity.key;
'''
if new_identity not in start_body:
    count = start_body.count(old_identity)
    if count != 1:
        raise SystemExit(f'logical identity anchor mismatch: {count}')
    start_body = start_body.replace(old_identity, new_identity, 1)

old_reconstructed_fence = '          if (candidateLogicalId != logicalId) continue;'
new_reconstructed_fence = '''          if (candidateLogicalId == null ||
              !logicalIdentity.matchesPersistedKey(candidateLogicalId)) {
            continue;
          }'''
if new_reconstructed_fence not in start_body:
    count = start_body.count(old_reconstructed_fence)
    if count != 1:
        raise SystemExit(f'reconstructed identity fence mismatch: {count}')
    start_body = start_body.replace(
        old_reconstructed_fence,
        new_reconstructed_fence,
        1,
    )

old_known_identity_fence = '            if (candidateLogicalId != logicalId) continue;'
new_known_identity_fence = (
    '            if (!logicalIdentity.matchesPersistedKey(candidateLogicalId)) continue;'
)
if new_known_identity_fence not in start_body:
    count = start_body.count(old_known_identity_fence)
    if count != 1:
        raise SystemExit(f'known identity fence mismatch: {count}')
    start_body = start_body.replace(
        old_known_identity_fence,
        new_known_identity_fence,
        1,
    )

source = source[:start] + start_body + source[complete:]

complete = source.find(complete_sig, start)
drop = source.find(drop_sig, complete)
if drop < 0:
    raise SystemExit('_dropCompleteRecords missing')
complete_body = source[complete:drop]

storage_anchor = '    final storage = _ref.read(storageServiceProvider);\n'
logical_identity_block = '''    final logicalIdentity = DownloadLogicalIdentity.fromMedia(
      item: item,
      episode: episode,
    );
'''
if logical_identity_block not in complete_body:
    count = complete_body.count(storage_anchor)
    if count != 1:
        raise SystemExit(f'complete identity insertion anchor mismatch: {count}')
    complete_body = complete_body.replace(
        storage_anchor,
        storage_anchor + logical_identity_block,
        1,
    )

old_complete_match = '''      if (candidateLogicalId != null) {
        if (candidateLogicalId == logicalId) matches.add(record);
        continue;
      }
'''
new_complete_match = '''      if (candidateLogicalId != null) {
        if (candidateLogicalId == logicalId ||
            logicalIdentity.matchesPersistedKey(candidateLogicalId)) {
          matches.add(record);
        }
        continue;
      }
'''
if new_complete_match not in complete_body:
    count = complete_body.count(old_complete_match)
    if count != 1:
        raise SystemExit(f'complete identity match anchor mismatch: {count}')
    complete_body = complete_body.replace(old_complete_match, new_complete_match, 1)

source = source[:complete] + complete_body + source[drop:]
path.write_text(source)

updated = path.read_text()
start = updated.find(start_sig)
complete = updated.find(complete_sig, start)
drop = updated.find(drop_sig, complete)
start_body = updated[start:complete]
complete_body = updated[complete:drop]

required_start = [
    'final logicalIdentity = DownloadLogicalIdentity.fromMedia',
    'final logicalId = logicalIdentity.key',
    'final allJobs = await _jobStore.all()',
    '!logicalIdentity.matchesPersistedKey(candidateLogicalId)',
    'Pre-logical-identity migration fallback',
    'if (candidateTracking == (trackingUrl ?? url))',
]
for invariant in required_start:
    if invariant not in start_body:
        raise SystemExit(f'missing start/adoption invariant: {invariant}')
if 'candidateLogicalId != logicalId' in start_body:
    raise SystemExit('raw logical-id inequality remains in start/adoption path')
if start_body.count('logicalIdentity.matchesPersistedKey(candidateLogicalId)') < 2:
    raise SystemExit('alias-aware start/adoption fences are incomplete')

required_complete = [
    'DownloadLogicalIdentity.fromMedia',
    'logicalDownloadIdFromMetadata',
    'logicalIdentity.matchesPersistedKey(candidateLogicalId)',
    'Pre-logical-identity migration fallback',
]
for invariant in required_complete:
    if invariant not in complete_body:
        raise SystemExit(f'missing complete-record invariant: {invariant}')
