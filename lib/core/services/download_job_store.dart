import 'package:hive_flutter/hive_flutter.dart';

import 'download_job_state.dart';

const int kDownloadJobSchemaVersion = 1;
const String kDownloadJobStoreBox = 'download_job_store_v1';

/// Durable identity of the remote object whose bytes are stored locally.
///
/// A strong ETag is preferred, Last-Modified is a fallback, and expected size
/// plus final URL give us additional evidence when a provider refreshes a
/// signed CDN URL. The store never silently replaces an incompatible
/// fingerprint because doing so could attach old bytes to a different object.
class DownloadResourceFingerprint {
  const DownloadResourceFingerprint({
    this.strongEtag,
    this.lastModified,
    this.expectedBytes = -1,
    this.finalUrl,
  });

  final String? strongEtag;
  final String? lastModified;
  final int expectedBytes;
  final String? finalUrl;

  bool get hasIdentityEvidence =>
      (strongEtag?.trim().isNotEmpty ?? false) ||
      (lastModified?.trim().isNotEmpty ?? false) ||
      expectedBytes > 0 ||
      (finalUrl?.trim().isNotEmpty ?? false);

  Map<String, Object?> toJson() => <String, Object?>{
    if (strongEtag?.trim().isNotEmpty ?? false) 'strongEtag': strongEtag,
    if (lastModified?.trim().isNotEmpty ?? false)
      'lastModified': lastModified,
    if (expectedBytes > 0) 'expectedBytes': expectedBytes,
    if (finalUrl?.trim().isNotEmpty ?? false) 'finalUrl': finalUrl,
  };

  static DownloadResourceFingerprint? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final fingerprint = DownloadResourceFingerprint(
      strongEtag: _nonEmptyString(map['strongEtag']),
      lastModified: _nonEmptyString(map['lastModified']),
      expectedBytes: _intValue(map['expectedBytes'], fallback: -1),
      finalUrl: _nonEmptyString(map['finalUrl']),
    );
    return fingerprint.hasIdentityEvidence ? fingerprint : null;
  }

  /// Returns false only when both sides contain comparable evidence that
  /// conflicts. Missing evidence is treated as unknown rather than mismatch.
  bool compatibleWith(DownloadResourceFingerprint other) {
    final aEtag = _nonEmptyString(strongEtag);
    final bEtag = _nonEmptyString(other.strongEtag);
    if (aEtag != null && bEtag != null && aEtag != bEtag) return false;

    final aModified = _nonEmptyString(lastModified);
    final bModified = _nonEmptyString(other.lastModified);
    if (aEtag == null &&
        bEtag == null &&
        aModified != null &&
        bModified != null &&
        aModified != bModified) {
      return false;
    }

    if (expectedBytes > 0 &&
        other.expectedBytes > 0 &&
        expectedBytes != other.expectedBytes) {
      return false;
    }
    return true;
  }
}

/// One durable logical episode download.
///
/// The plugin database, URLSession/WorkManager tasks, multipart manifests and
/// UI providers are executors/views. This record is the target source of truth
/// while the downloader is migrated incrementally.
class DownloadJobRecord {
  const DownloadJobRecord({
    required this.taskId,
    required this.trackingUrl,
    required this.state,
    required this.generation,
    required this.durableBytes,
    required this.expectedBytes,
    required this.userPaused,
    required this.queueWaiting,
    required this.updatedAtMillis,
    this.fingerprint,
  });

  final String taskId;
  final String trackingUrl;
  final DownloadJobState state;
  final int generation;
  final int durableBytes;
  final int expectedBytes;
  final bool userPaused;
  final bool queueWaiting;
  final int updatedAtMillis;
  final DownloadResourceFingerprint? fingerprint;

  DownloadAttemptToken get attemptToken => DownloadAttemptToken(
    taskId: taskId,
    generation: generation,
  );

  DownloadJobRecord copyWith({
    String? trackingUrl,
    DownloadJobState? state,
    int? generation,
    int? durableBytes,
    int? expectedBytes,
    bool? userPaused,
    bool? queueWaiting,
    int? updatedAtMillis,
    DownloadResourceFingerprint? fingerprint,
    bool clearFingerprint = false,
  }) => DownloadJobRecord(
    taskId: taskId,
    trackingUrl: trackingUrl ?? this.trackingUrl,
    state: state ?? this.state,
    generation: generation ?? this.generation,
    durableBytes: durableBytes ?? this.durableBytes,
    expectedBytes: expectedBytes ?? this.expectedBytes,
    userPaused: userPaused ?? this.userPaused,
    queueWaiting: queueWaiting ?? this.queueWaiting,
    updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
    fingerprint: clearFingerprint ? null : (fingerprint ?? this.fingerprint),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': kDownloadJobSchemaVersion,
    'taskId': taskId,
    'trackingUrl': trackingUrl,
    'state': state.name,
    'generation': generation,
    'durableBytes': durableBytes,
    'expectedBytes': expectedBytes,
    'userPaused': userPaused,
    'queueWaiting': queueWaiting,
    'updatedAtMillis': updatedAtMillis,
    if (fingerprint != null) 'fingerprint': fingerprint!.toJson(),
  };

  static DownloadJobRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final taskId = _nonEmptyString(map['taskId']);
    final trackingUrl = _nonEmptyString(map['trackingUrl']);
    if (taskId == null || trackingUrl == null) return null;

    final generation = _intValue(map['generation']);
    final durableBytes = _intValue(map['durableBytes']);
    if (generation < 0 || durableBytes < 0) return null;

    return DownloadJobRecord(
      taskId: taskId,
      trackingUrl: trackingUrl,
      state: _jobStateValue(map['state']),
      generation: generation,
      durableBytes: durableBytes,
      expectedBytes: _intValue(map['expectedBytes'], fallback: -1),
      userPaused: map['userPaused'] == true,
      queueWaiting: map['queueWaiting'] == true,
      updatedAtMillis: _intValue(map['updatedAtMillis']),
      fingerprint: DownloadResourceFingerprint.fromJson(map['fingerprint']),
    );
  }
}

abstract interface class DownloadJobBackend {
  Future<Map<String, dynamic>?> read(String taskId);
  Future<List<Map<String, dynamic>>> readAll();
  Future<void> write(String taskId, Map<String, Object?> value);
  Future<void> delete(String taskId);
}

/// Hive backend kept separate from [DownloadJobStore] so state-machine tests do
/// not need a Flutter filesystem and future migrations can use another backend
/// without changing store invariants.
class HiveDownloadJobBackend implements DownloadJobBackend {
  const HiveDownloadJobBackend({this.boxName = kDownloadJobStoreBox});

  final String boxName;

  Future<Box<dynamic>> _box() => Hive.openBox<dynamic>(boxName);

  @override
  Future<Map<String, dynamic>?> read(String taskId) async {
    final raw = (await _box()).get(taskId);
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  @override
  Future<List<Map<String, dynamic>>> readAll() async {
    final box = await _box();
    final result = <Map<String, dynamic>>[];
    for (final value in box.values) {
      if (value is Map) result.add(Map<String, dynamic>.from(value));
    }
    return result;
  }

  @override
  Future<void> write(String taskId, Map<String, Object?> value) async {
    await (await _box()).put(taskId, value);
  }

  @override
  Future<void> delete(String taskId) async {
    await (await _box()).delete(taskId);
  }
}

class DownloadJobStore {
  DownloadJobStore(this.backend);

  final DownloadJobBackend backend;
  Future<void> _writeChain = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() action) {
    final done = Completer<void>();
    final previous = _writeChain;
    _writeChain = previous.catchError((_) {}).whenComplete(() => done.future);
    return previous.catchError((_) {}).then((_) async {
      try {
        return await action();
      } finally {
        if (!done.isCompleted) done.complete();
      }
    });
  }

  Future<DownloadJobRecord?> get(String taskId) async {
    final id = taskId.trim();
    if (id.isEmpty) return null;
    return DownloadJobRecord.fromJson(await backend.read(id));
  }

  Future<List<DownloadJobRecord>> all() async {
    final jobs = <DownloadJobRecord>[];
    for (final raw in await backend.readAll()) {
      final job = DownloadJobRecord.fromJson(raw);
      if (job != null) jobs.add(job);
    }
    jobs.sort((a, b) => a.updatedAtMillis.compareTo(b.updatedAtMillis));
    return jobs;
  }

  /// Persist a newer view of a logical job.
  ///
  /// Returns false for stale or unsafe writes instead of allowing a late
  /// callback to regress durable state. The only supported way to intentionally
  /// restart from byte zero is to [remove] the job first (the user-delete path).
  Future<bool> put(DownloadJobRecord next) => _serialize(() => _putUnlocked(next));

  Future<bool> _putUnlocked(DownloadJobRecord next) async {
    final taskId = next.taskId.trim();
    final trackingUrl = next.trackingUrl.trim();
    if (taskId.isEmpty || trackingUrl.isEmpty) return false;
    if (next.generation < 0 || next.durableBytes < 0) return false;

    final current = await get(taskId);
    if (current != null) {
      if (current.state == DownloadJobState.completed &&
          next.state != DownloadJobState.completed) {
        return false;
      }
      if (next.generation < current.generation) return false;
      if (next.durableBytes < current.durableBytes) return false;
      if (current.expectedBytes > 0 &&
          next.expectedBytes > 0 &&
          current.expectedBytes != next.expectedBytes) {
        return false;
      }
      if (current.trackingUrl != trackingUrl) return false;
      final oldFingerprint = current.fingerprint;
      final newFingerprint = next.fingerprint;
      if (oldFingerprint != null &&
          newFingerprint != null &&
          !oldFingerprint.compatibleWith(newFingerprint)) {
        return false;
      }
    }

    await backend.write(taskId, next.toJson());
    return true;
  }

  /// Start a new execution generation atomically. The durable bytes and
  /// fingerprint are inherited; beginning an attempt can never reset progress.
  Future<DownloadAttemptToken?> beginAttempt(
    String taskId, {
    DownloadJobState state = DownloadJobState.starting,
    int? updatedAtMillis,
  }) => _serialize(() async {
    final current = await get(taskId);
    if (current == null || current.state == DownloadJobState.completed) {
      return null;
    }
    final next = current.copyWith(
      state: state,
      generation: current.generation + 1,
      updatedAtMillis:
          updatedAtMillis ?? DateTime.now().millisecondsSinceEpoch,
    );
    if (!await _putUnlocked(next)) return null;
    return next.attemptToken;
  });

  /// Apply one callback/result only when it belongs to the active generation.
  /// This is the durable counterpart of [DownloadAttemptFence].
  Future<bool> updateForAttempt(
    DownloadAttemptToken token, {
    DownloadJobState? state,
    int? durableBytes,
    int? expectedBytes,
    bool? userPaused,
    bool? queueWaiting,
    DownloadResourceFingerprint? fingerprint,
    int? updatedAtMillis,
  }) => _serialize(() async {
    final current = await get(token.taskId);
    if (current == null || current.generation != token.generation) return false;
    return _putUnlocked(
      current.copyWith(
        state: state,
        durableBytes: durableBytes,
        expectedBytes: expectedBytes,
        userPaused: userPaused,
        queueWaiting: queueWaiting,
        fingerprint: fingerprint,
        updatedAtMillis:
            updatedAtMillis ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  });

  Future<void> remove(String taskId) =>
      _serialize(() => backend.delete(taskId.trim()));

  /// Durable generation check for async callbacks after relaunch.
  Future<bool> accepts(DownloadAttemptToken token) async {
    if (token.generation <= 0) return false;
    final job = await get(token.taskId);
    return job != null && job.generation == token.generation;
  }
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int _intValue(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

DownloadJobState _jobStateValue(Object? raw) {
  final name = raw?.toString();
  for (final state in DownloadJobState.values) {
    if (state.name == name) return state;
  }
  // Unknown future/legacy state must never be interpreted as completed or a
  // fresh start. Interrupted is the conservative recoverable representation.
  return DownloadJobState.interrupted;
}
