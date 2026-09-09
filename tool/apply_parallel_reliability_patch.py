from pathlib import Path


def replace_one(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    return text.replace(old, new, 1)

# Seedable connection governor -------------------------------------------------
gov_path = Path('lib/core/services/download_connection_governor.dart')
gov = gov_path.read_text()
gov = replace_one(
    gov,
    "  final Map<String, _HostProbeState> _hostProbeStates =\n      <String, _HostProbeState>{};\n\n  int connectionCeilingFor(String url, {required int requested}) {",
    "  final Map<String, _HostProbeState> _hostProbeStates =\n      <String, _HostProbeState>{};\n\n  /// Restore safe host ceilings learned during earlier app sessions.\n  /// Existing in-process pressure always wins by keeping the lower ceiling.\n  void seedHostCeilings(Map<String, int> ceilings) {\n    final nextProbe = _now().add(kDownloadHostProbeCooldown);\n    for (final entry in ceilings.entries) {\n      final key = downloadOriginKey(entry.key);\n      if (key.trim().isEmpty) continue;\n      final safe = _safeCeiling(entry.value);\n      final current = _learnedHostCeilings[key];\n      _learnedHostCeilings[key] = current == null || safe < current\n          ? safe\n          : current;\n      _hostProbeStates.putIfAbsent(\n        key,\n        () => _HostProbeState(nextProbeAt: nextProbe),\n      );\n    }\n  }\n\n  int connectionCeilingFor(String url, {required int requested}) {",
    'governor seed method',
)
gov_path.write_text(gov)

# Multipart scheduler + assembly ---------------------------------------------
pp_path = Path('lib/core/services/persistent_parallel_download.dart')
pp = pp_path.read_text()
pp = replace_one(
    pp,
    "const Duration kParallelTailStallDelay = Duration(seconds: 20);",
    "const Duration kParallelTailStallDelay = Duration(seconds: 20);\n\n/// Persist host throughput samples at a low cadence so the next episode can\n/// reuse a proven connection ceiling without writing Hive on every callback.\nconst Duration kParallelHostProfileSampleInterval = Duration(seconds: 5);",
    'profile sample interval',
)
pp = replace_one(
    pp,
    "    this.tailStallDelay = kParallelTailStallDelay,\n    this.maxActiveConnections = kDownloadGlobalConnectionBudget,\n  });",
    "    this.tailStallDelay = kParallelTailStallDelay,\n    this.maxActiveConnections = kDownloadGlobalConnectionBudget,\n    this.onHostPressure,\n    this.onHostSample,\n  });",
    'constructor callbacks',
)
pp = replace_one(
    pp,
    "  final Duration recoveryDelay;\n  final Duration tailStallDelay;\n\n  final Map<String, _ParallelSession> _sessions = {};",
    "  final Duration recoveryDelay;\n  final Duration tailStallDelay;\n  final void Function(String url, int fallbackCeiling)? onHostPressure;\n  final void Function(\n    String url,\n    int activeConnections,\n    double bytesPerSecond,\n  )? onHostSample;\n\n  final Map<String, _ParallelSession> _sessions = {};",
    'callback fields',
)
pp = replace_one(
    pp,
    "  int get activeConnectionCount => _activeConnectionIds.length;\n\n  int get _connectionBudget =>",
    "  int get activeConnectionCount => _activeConnectionIds.length;\n\n  void seedHostCeilings(Map<String, int> ceilings) =>\n      _connectionGovernor.seedHostCeilings(ceilings);\n\n  int get _connectionBudget =>",
    'public seed hook',
)
pp = replace_one(
    pp,
    "      final learned = _connectionGovernor.learnHostCeiling(\n        session.task.url,\n        fallback,\n      );\n      for (final sibling in _sessions.values) {",
    "      final learned = _connectionGovernor.learnHostCeiling(\n        session.task.url,\n        fallback,\n      );\n      onHostPressure?.call(session.task.url, learned);\n      for (final sibling in _sessions.values) {",
    'persist host pressure',
)
pp = replace_one(
    pp,
    "    final timeRemaining = _aggregateTimeRemaining(session, speed);\n\n    await saveRecord(",
    "    final timeRemaining = _aggregateTimeRemaining(session, speed);\n\n    if (speed > 0) {\n      final now = DateTime.now();\n      final previousSample = session.lastHostProfileSampleAt;\n      if (previousSample == null ||\n          now.difference(previousSample) >= kParallelHostProfileSampleInterval) {\n        session.lastHostProfileSampleAt = now;\n        onHostSample?.call(\n          session.task.url,\n          _activeConnectionsForSession(session).clamp(1, 1 << 30),\n          speed * 1000 * 1000,\n        );\n      }\n    }\n\n    await saveRecord(",
    'throughput sampling',
)
old_assemble = """  Future<void> _assemble(_ParallelSession session) async {
    final target = File(await session.task.filePath());
    final staging = File('${target.path}.assembling');
    final output = await staging.open(mode: FileMode.write);
    try {
      for (final part in session.parts) {
        final file = File(await part.task.filePath());
        if (await file.length() != part.size) {
          throw StateError('Part size changed');
        }
        await for (final bytes in file.openRead()) {
          if (session.deleted) return;
          await output.writeFrom(bytes);
        }
      }
      await output.flush();
    } finally {
      await output.close();
    }
    if (session.deleted) return;
    if (await staging.length() != session.size) {
      throw StateError('Incomplete assembly');
    }
    if (await target.exists()) await target.delete();
    await staging.rename(target.path);
    await _finishCompleteSession(session);
  }
"""
new_assemble = """  Future<void> _assemble(_ParallelSession session) async {
    final target = File(await session.task.filePath());
    if (await target.exists()) {
      if (await target.length() == session.size) {
        await _finishCompleteSession(session);
        return;
      }
      // Never overwrite an unexpected user-visible file during automatic
      // recovery. The user can remove/rename it explicitly and resume later.
      throw StateError('Download target already exists with a different size');
    }

    final staging = File('${target.path}.assembling');
    final output = await staging.open(mode: FileMode.write);
    try {
      // Establish the final logical length up front. Besides reducing repeated
      // growth metadata work, this surfaces many disk-full failures before all
      // parts are copied into a staging file.
      await output.truncate(session.size);
      await output.setPosition(0);
      var assembledBytes = 0;
      for (final part in session.parts) {
        final file = File(await part.task.filePath());
        if (!await file.exists() || await file.length() != part.size) {
          throw StateError('Part size changed');
        }
        await for (final bytes in file.openRead()) {
          if (session.deleted) return;
          if (assembledBytes + bytes.length > session.size) {
            throw StateError('Assembly exceeded expected size');
          }
          await output.writeFrom(bytes);
          assembledBytes += bytes.length;
        }
      }
      if (assembledBytes != session.size) {
        throw StateError('Incomplete assembly');
      }
      await output.flush();
    } finally {
      await output.close();
    }
    if (session.deleted) return;
    if (!await staging.exists() || await staging.length() != session.size) {
      throw StateError('Incomplete assembly');
    }
    // The target was proven absent above. Rename staging atomically so a crash
    // leaves either the recoverable .assembling file or the full final file.
    await staging.rename(target.path);
    await _finishCompleteSession(session);
  }
"""
pp = replace_one(pp, old_assemble, new_assemble, 'safe assembly')
pp = replace_one(
    pp,
    "  Timer? aggregateProgressTimer;\n  bool aggregateProgressDirty = false;\n  Future<void> _pending = Future<void>.value();",
    "  Timer? aggregateProgressTimer;\n  bool aggregateProgressDirty = false;\n  DateTime? lastHostProfileSampleAt;\n  Future<void> _pending = Future<void>.value();",
    'session profile timestamp',
)
pp_path.write_text(pp)
print('parallel reliability patch applied')
