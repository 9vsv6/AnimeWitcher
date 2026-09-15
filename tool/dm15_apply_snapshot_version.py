from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'missing {label} anchor')
    return text.replace(old, new, 1)

# Dart bridge: give every correctness-sensitive queue checkpoint a monotonic
# process version, require an explicit native acknowledgement, and retry once
# above the native durable high-water mark after a restart/stale write.
dart_path = Path('lib/core/services/download_continued_processing_service.dart')
dart = dart_path.read_text()
dart = replace_once(
    dart,
    "  bool _disposed = false;\n",
    "  bool _disposed = false;\n  int _nativeQueueSnapshotVersion = 0;\n",
    'Dart version field',
)
dart = replace_once(
    dart,
    "  Future<void> persistNativeQueue({\n",
    "  Future<int?> persistNativeQueue({\n",
    'Dart persist signature',
)
dart = replace_once(
    dart,
    "  }) async {\n    await _invoke('persistNativeQueue', <String, Object>{\n      'maxConcurrent': maxConcurrent,\n",
    """  }) async {
    int nextVersion() {
      final wallClock = DateTime.now().microsecondsSinceEpoch;
      final next = _nativeQueueSnapshotVersion + 1;
      _nativeQueueSnapshotVersion = wallClock > next ? wallClock : next;
      return _nativeQueueSnapshotVersion;
    }

    Future<int?> write(int snapshotVersion) async {
      final ack = await _invokeForResult<Object?>(
        'persistNativeQueue',
        <String, Object>{
      'snapshotVersion': snapshotVersion,
      'maxConcurrent': maxConcurrent,
""",
    'Dart persist body start',
)
dart = replace_once(
    dart,
    "      'multipartPlans': multipartPlans,\n    });\n  }\n\n  Future<dynamic> _handleNativeCall",
    """      'multipartPlans': multipartPlans,
        },
      );
      if (ack is! Map) return null;
      final rawAcceptedVersion = ack['acceptedVersion'];
      if (rawAcceptedVersion is! num) return null;
      return rawAcceptedVersion.toInt();
    }

    final snapshotVersion = nextVersion();
    final accepted = await write(snapshotVersion);
    if (accepted == null) return null;
    if (accepted > _nativeQueueSnapshotVersion) {
      _nativeQueueSnapshotVersion = accepted;
    }
    if (accepted == snapshotVersion) return accepted;

    // Native persisted a newer snapshot (for example while Flutter slept).
    // Re-issue this *current* Dart projection above that durable high-water
    // mark instead of silently treating the stale write as successful.
    final retryVersion = nextVersion();
    final retried = await write(retryVersion);
    if (retried != null && retried > _nativeQueueSnapshotVersion) {
      _nativeQueueSnapshotVersion = retried;
    }
    return retried == retryVersion ? retried : null;
  }

  Future<dynamic> _handleNativeCall""",
    'Dart persist body end',
)
dart = replace_once(
    dart,
    "  Future<void> _invoke(String method, Map<String, Object> arguments) async {\n",
    """  Future<T?> _invokeForResult<T>(
    String method,
    Map<String, Object> arguments,
  ) async {
    if (!_isAvailable || _disposed) return null;

    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[DownloadContinuedProcessing] $method failed: '
          '${error.code} ${error.message}',
        );
      }
      return null;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[DownloadContinuedProcessing] $method failed: $error');
      }
      return null;
    }
  }

  Future<void> _invoke(String method, Map<String, Object> arguments) async {
""",
    'Dart result invoke helper',
)
dart_path.write_text(dart)

# Swift durable state: persist the accepted version with UserDefaults state and
# refuse an older snapshot before mutating any native queue fields.
swift_path = Path('ios/Runner/DownloadNativeWaitingQueue.swift')
swift = swift_path.read_text()
swift = replace_once(
    swift,
    "  struct State: Codable {\n    var maxConcurrent: Int\n",
    "  struct State: Codable {\n    var snapshotVersion: Int\n    var maxConcurrent: Int\n",
    'Swift State version field',
)
swift = replace_once(
    swift,
    "    init(\n      maxConcurrent: Int,\n",
    "    init(\n      snapshotVersion: Int = 0,\n      maxConcurrent: Int,\n",
    'Swift State init version arg',
)
swift = replace_once(
    swift,
    "    ) {\n      self.maxConcurrent = maxConcurrent\n",
    "    ) {\n      self.snapshotVersion = snapshotVersion\n      self.maxConcurrent = maxConcurrent\n",
    'Swift State init assignment',
)
swift = replace_once(
    swift,
    "      let container = try decoder.container(keyedBy: CodingKeys.self)\n      maxConcurrent = try container.decodeIfPresent(Int.self, forKey: .maxConcurrent) ?? 1\n",
    "      let container = try decoder.container(keyedBy: CodingKeys.self)\n      snapshotVersion = try container.decodeIfPresent(Int.self, forKey: .snapshotVersion) ?? 0\n      maxConcurrent = try container.decodeIfPresent(Int.self, forKey: .maxConcurrent) ?? 1\n",
    'Swift State decoder version',
)
swift = replace_once(
    swift,
    "  static func persist(from arguments: [String: Any]) {\n    lock.lock()\n    defer { lock.unlock() }\n    let current = loadLocked()\n",
    """  @discardableResult
  static func persist(from arguments: [String: Any]) -> Int {
    lock.lock()
    defer { lock.unlock() }
    let current = loadLocked()
    let snapshotVersion = intValue(arguments["snapshotVersion"])
    if let snapshotVersion, snapshotVersion < current.snapshotVersion {
      return current.snapshotVersion
    }
    if let snapshotVersion, snapshotVersion == current.snapshotVersion {
      return current.snapshotVersion
    }
    // Legacy callers receive a native-allocated next version. Updated Dart
    // always supplies its own monotonic version and receives it back as ack.
    let acceptedVersion = snapshotVersion ?? (current.snapshotVersion + 1)
""",
    'Swift persist version gate',
)
swift = replace_once(
    swift,
    "      State(\n        maxConcurrent: maxConcurrent,\n",
    "      State(\n        snapshotVersion: acceptedVersion,\n        maxConcurrent: maxConcurrent,\n",
    'Swift persisted accepted version',
)
swift = replace_once(
    swift,
    "    )\n  }\n\n  static func load() -> State {\n",
    "    )\n    return acceptedVersion\n  }\n\n  static func load() -> State {\n",
    'Swift persist ack return',
)
swift_path.write_text(swift)

# Method-channel acknowledgement: return the durable version, not a generic
# `true`, so Dart can distinguish accepted, stale and failed checkpoints.
app_path = Path('ios/Runner/AppDelegate.swift')
app = app_path.read_text()
app = replace_once(
    app,
    """        DownloadNativeWaitingQueue.persist(from: arguments)
        DownloadNativeWaitingQueue.promoteMultipartIfPossible()
        result(true)
""",
    """        let acceptedVersion = DownloadNativeWaitingQueue.persist(from: arguments)
        DownloadNativeWaitingQueue.promoteMultipartIfPossible()
        result(["acceptedVersion": acceptedVersion])
""",
    'AppDelegate native queue ack',
)
app_path.write_text(app)
