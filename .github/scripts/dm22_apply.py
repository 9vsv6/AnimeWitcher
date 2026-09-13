from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f"DM-22 anchor drifted: {label}")
    return text.replace(old, new, 1)


parallel_path = Path('lib/core/services/persistent_parallel_download.dart')
service_path = Path('lib/core/services/download_service.dart')
swift_path = Path('ios/Runner/DownloadNativeWaitingQueue.swift')
parallel = parallel_path.read_text()
service = service_path.read_text()
swift = swift_path.read_text()

# Dart side: exporting a child is an ownership offer, not a plain task list.
old_plan = '''class NativeParallelBackgroundPlan {
  const NativeParallelBackgroundPlan({
    required this.parentTaskId,
    required this.maxConcurrent,
    required this.tasks,
  });

  final String parentTaskId;
  final int maxConcurrent;
  final List<DownloadTask> tasks;
}'''
new_plan = '''const Duration kNativeMultipartClaimOfferLease = Duration(minutes: 15);

class NativeParallelBackgroundCandidate {
  const NativeParallelBackgroundCandidate({
    required this.task,
    required this.generation,
    required this.claimId,
    required this.claimLease,
  });

  final DownloadTask task;
  final int generation;
  final String claimId;
  final Duration claimLease;
}

class NativeParallelBackgroundPlan {
  const NativeParallelBackgroundPlan({
    required this.parentTaskId,
    required this.maxConcurrent,
    required this.candidates,
  });

  final String parentTaskId;
  final int maxConcurrent;
  final List<NativeParallelBackgroundCandidate> candidates;
}'''
parallel = replace_once(parallel, old_plan, new_plan, 'Dart plan model')

old_fields = '''  final Map<String, _ParallelSession> _sessions = {};
  final Map<String, _ParallelSession> _children = {};
  final Set<String> _activeConnectionIds = {};
  final DownloadConnectionGovernor _connectionGovernor ='''
new_fields = '''  final Map<String, _ParallelSession> _sessions = {};
  final Map<String, _ParallelSession> _children = {};
  final Set<String> _activeConnectionIds = {};
  final Map<String, ({int generation, DateTime expiresAt, String claimId})>
  _nativeClaimOffers = {};
  final DownloadConnectionGovernor _connectionGovernor ='''
parallel = replace_once(parallel, old_fields, new_fields, 'Dart claim-offer storage')

method_start = parallel.index('  List<NativeParallelBackgroundPlan> nativeBackgroundPlans() {')
method_end = parallel.index('\n  /// Repair a child', method_start)
old_method = parallel[method_start:method_end]
new_method = '''  List<NativeParallelBackgroundPlan> nativeBackgroundPlans() {
    if (_disposed) return const <NativeParallelBackgroundPlan>[];
    final plans = <NativeParallelBackgroundPlan>[];
    final now = DateTime.now();
    for (final session in _sessions.values) {
      if (!session.active || session.pauseRequested || session.deleted) {
        continue;
      }
      final provenWidth = _activeConnectionsForSession(session);
      if (provenWidth <= 0) continue;
      final candidates = <NativeParallelBackgroundCandidate>[];
      for (final part in session.parts) {
        if (part.complete ||
            part.launched ||
            part.recoveryTimer != null ||
            part.attemptGeneration <= 0 ||
            part.sourceValidationRequired ||
            part.progress > 0 ||
            part.credibleProgress > 0) {
          continue;
        }
        final existing = _nativeClaimOffers[part.task.taskId];
        final offer = existing != null &&
                existing.generation == part.attemptGeneration &&
                existing.expiresAt.isAfter(now)
            ? existing
            : (
                generation: part.attemptGeneration,
                expiresAt: now.add(kNativeMultipartClaimOfferLease),
                claimId:
                    '${session.task.taskId}:${part.task.taskId}:g${part.attemptGeneration}:o${now.microsecondsSinceEpoch}',
              );
        _nativeClaimOffers[part.task.taskId] = offer;
        candidates.add(
          NativeParallelBackgroundCandidate(
            task: part.task,
            generation: offer.generation,
            claimId: offer.claimId,
            claimLease: kNativeMultipartClaimOfferLease,
          ),
        );
      }
      if (candidates.isEmpty) continue;
      plans.add(
        NativeParallelBackgroundPlan(
          parentTaskId: session.task.taskId,
          maxConcurrent: provenWidth.clamp(1, kDownloadGlobalConnectionBudget),
          candidates: candidates,
        ),
      );
    }
    return plans;
  }
'''
if 'final candidates = <NativeParallelBackgroundCandidate>[];' not in old_method:
    parallel = parallel[:method_start] + new_method + parallel[method_end:]

old_launchable = '''  Iterable<_DownloadPart> _launchableParts(_ParallelSession session) =>
      session.parts.where(
        (part) =>
            !part.complete && !part.launched && part.recoveryTimer == null,
      );'''
new_launchable = '''  bool _hasActiveNativeClaimOffer(_DownloadPart part) {
    final offer = _nativeClaimOffers[part.task.taskId];
    if (offer == null) return false;
    if (offer.generation != part.attemptGeneration ||
        !offer.expiresAt.isAfter(DateTime.now())) {
      _nativeClaimOffers.remove(part.task.taskId);
      return false;
    }
    return true;
  }

  Iterable<_DownloadPart> _launchableParts(_ParallelSession session) =>
      session.parts.where(
        (part) =>
            !part.complete &&
            !part.launched &&
            part.recoveryTimer == null &&
            !_hasActiveNativeClaimOffer(part),
      );'''
parallel = replace_once(parallel, old_launchable, new_launchable, 'Dart launch fence')
parallel_path.write_text(parallel)

# Snapshot carries the exact attempt + claim token across the bridge.
pattern = re.compile(
    r"'waiters': <Map<String, Object>>\[\s*for \(final child in plan\.tasks\) nativeWaitingPayload\(child\),\s*\],"
)
replacement = ''''waiters': <Map<String, Object>>[
            for (final child in plan.candidates)
              <String, Object>{
                ...nativeWaitingPayload(child.task),
                'generation': child.generation,
                'claimId': child.claimId,
                'claimLeaseMillis': child.claimLease.inMilliseconds,
              },
          ],'''
if "'generation': child.generation" not in service:
    service, count = pattern.subn(replacement, service, count=1)
    if count != 1:
        raise SystemExit('DM-22 anchor drifted: Dart native snapshot export')
service_path.write_text(service)

# Swift waiter + persistent state carry the claim through relaunch/suspension.
old_waiter_fields = '''    var resumeDataBase64: String?
    var progress: Double?
    var expectedBytes: Int64?
'''
new_waiter_fields = '''    var resumeDataBase64: String?
    var progress: Double?
    var expectedBytes: Int64?
    var generation: Int?
    var claimId: String?
    var claimLeaseMillis: Int?
'''
swift = replace_once(swift, old_waiter_fields, new_waiter_fields, 'Swift waiter claim fields')
old_waiter_init = '''        resumeDataBase64: string(arguments["resumeDataBase64"]),
        progress: doubleValue(arguments["progress"]),
        expectedBytes: int64Value(arguments["expectedBytes"])
      )'''
new_waiter_init = '''        resumeDataBase64: string(arguments["resumeDataBase64"]),
        progress: doubleValue(arguments["progress"]),
        expectedBytes: int64Value(arguments["expectedBytes"]),
        generation: intValue(arguments["generation"]),
        claimId: string(arguments["claimId"]),
        claimLeaseMillis: intValue(arguments["claimLeaseMillis"])
      )'''
swift = replace_once(swift, old_waiter_init, new_waiter_init, 'Swift waiter decode')

running_anchor = '''  struct RunningSample: Codable, Equatable {
'''
claim_struct = '''  struct MultipartClaim: Codable, Equatable, Sendable {
    var parentTaskId: String
    var maxConcurrent: Int
    var waiter: Waiter
    var generation: Int
    var claimId: String
    var expiresAtMillis: Int64
    var launchCommitted: Bool
  }

  struct RunningSample: Codable, Equatable {
'''
swift = replace_once(swift, running_anchor, claim_struct, 'Swift claim model')

swift = replace_once(
    swift,
    '    var multipartPlans: [MultipartPlan]\n',
    '    var multipartPlans: [MultipartPlan]\n    var multipartClaims: [MultipartClaim]\n',
    'Swift State claim field',
)
swift = replace_once(
    swift,
    '      runningSamples: [String: RunningSample] = [:],\n      multipartPlans: [MultipartPlan] = []\n    ) {',
    '      runningSamples: [String: RunningSample] = [:],\n      multipartPlans: [MultipartPlan] = [],\n      multipartClaims: [MultipartClaim] = []\n    ) {',
    'Swift State init argument',
)
swift = replace_once(
    swift,
    '      self.runningSamples = runningSamples\n      self.multipartPlans = multipartPlans\n    }',
    '      self.runningSamples = runningSamples\n      self.multipartPlans = multipartPlans\n      self.multipartClaims = multipartClaims\n    }',
    'Swift State init assignment',
)
swift = replace_once(
    swift,
    '      multipartPlans = try container.decodeIfPresent([MultipartPlan].self, forKey: .multipartPlans) ?? []\n    }',
    '      multipartPlans = try container.decodeIfPresent([MultipartPlan].self, forKey: .multipartPlans) ?? []\n      multipartClaims = try container.decodeIfPresent([MultipartClaim].self, forKey: .multipartClaims) ?? []\n    }',
    'Swift State decode',
)

# Reconcile claim leases before accepting a new snapshot. Active claims are
# removed from every incoming plan so stale/new snapshots cannot reintroduce them.
swift = replace_once(
    swift,
    '    let current = loadLocked()\n    let snapshotVersion = intValue(arguments["snapshotVersion"])',
    '    var current = loadLocked()\n    requeueExpiredMultipartClaimsLocked(&current)\n    let snapshotVersion = intValue(arguments["snapshotVersion"])',
    'Swift persist mutable current',
)
old_parse = '''    let dartMultipartPlans = dictionaryArray(arguments["multipartPlans"])
      .compactMap(MultipartPlan.from(arguments:))
    let released = Set(stringArray(arguments["queueWaitingTaskIds"]))'''
new_parse = '''    var dartMultipartPlans = dictionaryArray(arguments["multipartPlans"])
      .compactMap(MultipartPlan.from(arguments:))
    let claimedChildIds = Set(current.multipartClaims.map { $0.waiter.taskId })
    if !claimedChildIds.isEmpty {
      for index in dartMultipartPlans.indices {
        dartMultipartPlans[index].waiters.removeAll {
          claimedChildIds.contains($0.taskId)
        }
      }
    }
    let released = Set(stringArray(arguments["queueWaitingTaskIds"]))'''
swift = replace_once(swift, old_parse, new_parse, 'Swift snapshot claim filtering')
swift = replace_once(
    swift,
    '        runningSamples: current.runningSamples.filter { transferringSet.contains($0.key) },\n        multipartPlans: dartMultipartPlans\n      )',
    '        runningSamples: current.runningSamples.filter { transferringSet.contains($0.key) },\n        multipartPlans: dartMultipartPlans,\n        multipartClaims: current.multipartClaims\n      )',
    'Swift snapshot claim persistence',
)

helpers_anchor = '''  /// URLSession transport failures that are worth retrying without waking
'''
helpers = '''  private static func nowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
  }

  private static func requeueExpiredMultipartClaimsLocked(_ state: inout State) {
    let now = nowMillis()
    let expired = state.multipartClaims.filter { $0.expiresAtMillis <= now }
    guard !expired.isEmpty else { return }
    for claim in expired {
      if let index = state.multipartPlans.firstIndex(where: {
        $0.parentTaskId == claim.parentTaskId
      }) {
        if !state.multipartPlans[index].waiters.contains(where: {
          $0.taskId == claim.waiter.taskId
        }) {
          state.multipartPlans[index].waiters.insert(claim.waiter, at: 0)
        }
      } else {
        state.multipartPlans.append(
          MultipartPlan(
            parentTaskId: claim.parentTaskId,
            maxConcurrent: claim.maxConcurrent,
            waiters: [claim.waiter]
          )
        )
      }
    }
    let expiredIds = Set(expired.map { $0.claimId })
    state.multipartClaims.removeAll { expiredIds.contains($0.claimId) }
  }

  private static func releaseMultipartClaim(_ waiter: Waiter, requeue: Bool) {
    lock.lock()
    defer { lock.unlock() }
    var state = loadLocked()
    guard let claimId = waiter.claimId,
          let index = state.multipartClaims.firstIndex(where: {
            $0.claimId == claimId && $0.waiter.taskId == waiter.taskId
          })
    else { return }
    let claim = state.multipartClaims.remove(at: index)
    if requeue {
      if let planIndex = state.multipartPlans.firstIndex(where: {
        $0.parentTaskId == claim.parentTaskId
      }) {
        if !state.multipartPlans[planIndex].waiters.contains(where: {
          $0.taskId == waiter.taskId
        }) {
          state.multipartPlans[planIndex].waiters.insert(waiter, at: 0)
        }
      } else {
        state.multipartPlans.append(
          MultipartPlan(
            parentTaskId: claim.parentTaskId,
            maxConcurrent: claim.maxConcurrent,
            waiters: [waiter]
          )
        )
      }
    }
    saveLocked(state)
  }

  private static func commitMultipartClaimBeforeResume(_ waiter: Waiter) -> Bool {
    guard let claimId = waiter.claimId,
          let generation = waiter.generation
    else { return false }
    lock.lock()
    defer { lock.unlock() }
    var state = loadLocked()
    requeueExpiredMultipartClaimsLocked(&state)
    guard let index = state.multipartClaims.firstIndex(where: {
      $0.claimId == claimId &&
        $0.waiter.taskId == waiter.taskId &&
        $0.generation == generation
    }) else {
      saveLocked(state)
      return false
    }
    state.multipartClaims[index].launchCommitted = true
    state.multipartClaims[index].expiresAtMillis = nowMillis() + 15 * 60 * 1000
    saveLocked(state)
    return true
  }

  private static func settleMultipartClaim(childTaskId: String) {
    lock.lock()
    defer { lock.unlock() }
    var state = loadLocked()
    let oldCount = state.multipartClaims.count
    state.multipartClaims.removeAll { $0.waiter.taskId == childTaskId }
    if state.multipartClaims.count != oldCount {
      saveLocked(state)
    }
  }

  /// URLSession transport failures that are worth retrying without waking
'''
swift = replace_once(swift, helpers_anchor, helpers, 'Swift claim helpers')

old_selection = '''      let selected: [Waiter]
      lock.lock()
      var state = loadLocked()
      guard let index = state.multipartPlans.firstIndex(where: { $0.parentTaskId == parentId }) else {
        lock.unlock()
        return
      }
      var plan = state.multipartPlans[index]
      plan.waiters.removeAll { liveChildIds.contains($0.taskId) }
      let available = max(min(plan.maxConcurrent, 16) - liveChildIds.count, 0)
      selected = Array(plan.waiters.prefix(available))
      if !selected.isEmpty {
        let selectedIds = Set(selected.map(\\.taskId))
        plan.waiters.removeAll { selectedIds.contains($0.taskId) }
      }
      state.multipartPlans[index] = plan
      saveLocked(state)
      lock.unlock()'''
new_selection = '''      let selected: [Waiter]
      lock.lock()
      var state = loadLocked()
      requeueExpiredMultipartClaimsLocked(&state)
      guard let index = state.multipartPlans.firstIndex(where: { $0.parentTaskId == parentId }) else {
        lock.unlock()
        return
      }
      var plan = state.multipartPlans[index]
      plan.waiters.removeAll { liveChildIds.contains($0.taskId) }
      let claimedIds = Set(state.multipartClaims.map { $0.waiter.taskId })
      plan.waiters.removeAll { claimedIds.contains($0.taskId) }
      let available = max(min(plan.maxConcurrent, 16) - liveChildIds.count, 0)
      let claimable = plan.waiters.filter {
        ($0.generation ?? 0) > 0 &&
          !($0.claimId ?? "").isEmpty &&
          ($0.claimLeaseMillis ?? 0) > 0
      }
      selected = Array(claimable.prefix(available))
      if !selected.isEmpty {
        let selectedIds = Set(selected.map(\\.taskId))
        plan.waiters.removeAll { selectedIds.contains($0.taskId) }
        for claimedWaiter in selected {
          guard let generation = claimedWaiter.generation,
                let claimId = claimedWaiter.claimId,
                let lease = claimedWaiter.claimLeaseMillis
          else { continue }
          state.multipartClaims.removeAll {
            $0.waiter.taskId == claimedWaiter.taskId
          }
          state.multipartClaims.append(
            MultipartClaim(
              parentTaskId: parentId,
              maxConcurrent: plan.maxConcurrent,
              waiter: claimedWaiter,
              generation: generation,
              claimId: claimId,
              expiresAtMillis: nowMillis() + Int64(max(lease, 1)),
              launchCommitted: false
            )
          )
        }
      }
      state.multipartPlans[index] = plan
      saveLocked(state)
      lock.unlock()'''
swift = replace_once(swift, old_selection, new_selection, 'Swift atomic claim')

old_start = '''  private static func startMultipartChild(_ waiter: Waiter, on session: URLSession) {
    guard waiter.savedProgress <= 0,
          waiter.resumeDataBase64?.isEmpty ?? true,
          let url = URL(string: waiter.url)
    else { return }
    var request = URLRequest(url: url)'''
new_start = '''  private static func startMultipartChild(_ waiter: Waiter, on session: URLSession) {
    guard waiter.savedProgress <= 0,
          waiter.resumeDataBase64?.isEmpty ?? true,
          let url = URL(string: waiter.url)
    else {
      releaseMultipartClaim(waiter, requeue: true)
      return
    }
    guard !isAppInForeground() else {
      releaseMultipartClaim(waiter, requeue: true)
      return
    }
    var request = URLRequest(url: url)'''
swift = replace_once(swift, old_start, new_start, 'Swift child start guard')
old_resume = '''    task.taskDescription = waiter.taskDescription
    task.priority = URLSessionTask.highPriority
    DownloadNativeDiagnosticLog.record("background.multipart.promote", task: task)
    task.resume()
  }'''
new_resume = '''    task.taskDescription = waiter.taskDescription
    task.priority = URLSessionTask.highPriority
    guard !isAppInForeground(), commitMultipartClaimBeforeResume(waiter) else {
      task.cancel()
      releaseMultipartClaim(waiter, requeue: true)
      return
    }
    guard !isAppInForeground() else {
      task.cancel()
      releaseMultipartClaim(waiter, requeue: true)
      return
    }
    DownloadNativeDiagnosticLog.record("background.multipart.promote", task: task)
    task.resume()
  }'''
swift = replace_once(swift, old_resume, new_resume, 'Swift pre-resume claim check')

old_post_guard = '''    guard isDownloadPart(task),
          let childId = taskId(from: task),
          let parentId = parentTaskId(from: task)
    else {
      return
    }

    let now = CFAbsoluteTimeGetCurrent()'''
new_post_guard = '''    guard isDownloadPart(task),
          let childId = taskId(from: task),
          let parentId = parentTaskId(from: task)
    else {
      return
    }

    if totalWritten > 0 || completed {
      settleMultipartClaim(childTaskId: childId)
    }

    let now = CFAbsoluteTimeGetCurrent()'''
swift = replace_once(swift, old_post_guard, new_post_guard, 'Swift claim settlement')
swift_path.write_text(swift)

print('DM-22 production patch applied or already present')
