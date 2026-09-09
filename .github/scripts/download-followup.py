from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"expected one patch anchor in {path}, found {count}: {old[:140]!r}"
        )
    p.write_text(text.replace(old, new, 1))


service = "lib/core/services/download_service.dart"
replace_once(
    service,
    """      onPartProgress: (parent, child, progress) {
        if (!_disposed)
          _handleNativeChunkUpdate(
            parentTaskId: parent,
            chunkTaskId: child,
            progress: progress,
          );
      },""",
    """      onPartProgress: (parent, child, progress) {
        if (!_disposed) {
          _publishChunkProgress(
            parentTaskId: parent,
            chunkTaskId: child,
            progress: progress,
          );
        }
      },""",
)

replace_once(
    service,
    """  void _handleNativeChunkUpdate({
    required String parentTaskId,""",
    """  void _publishChunkProgress({
    required String parentTaskId,
    required String chunkTaskId,
    double? progress,
    int? statusOrdinal,
  }) {
    _ref
        .read(downloadChunkProgressProvider.notifier)
        .update(
          parentTaskId: parentTaskId,
          chunkTaskId: chunkTaskId,
          progress: progress,
          statusOrdinal: statusOrdinal,
        );
  }

  void _handleNativeChunkUpdate({
    required String parentTaskId,""",
)

replace_once(
    service,
    """    _ref
        .read(downloadChunkProgressProvider.notifier)
        .update(
          parentTaskId: parentTaskId,
          chunkTaskId: chunkTaskId,
          progress: derivedProgress,
          statusOrdinal: completed ? TaskStatus.complete.index : statusOrdinal,
        );

    unawaited(""",
    """    _publishChunkProgress(
      parentTaskId: parentTaskId,
      chunkTaskId: chunkTaskId,
      progress: derivedProgress,
      statusOrdinal: completed ? TaskStatus.complete.index : statusOrdinal,
    );

    unawaited(""",
)

continued = "lib/core/services/download_continued_processing_service.dart"
replace_once(continued, "import 'dart:io';", "import 'dart:async';\nimport 'dart:io';")
replace_once(
    continued,
    """  final SystemDownloadChunkUpdate? onChunkUpdate;
  bool _handlerInstalled = false;""",
    """  final SystemDownloadChunkUpdate? onChunkUpdate;
  bool _handlerInstalled = false;
  static const Duration _updateSampleInterval = Duration(seconds: 1);
  Timer? _updateTimer;
  DateTime? _lastUpdateAt;
  Map<String, Object>? _pendingUpdate;""",
)
replace_once(
    continued,
    """  Future<void> start({
    required String taskId,
    required String displayName,
    double progress = 0.0,
    int totalBytes = -1,
    int transferredBytes = 0,
    int completedCount = 0,
    int batchTotal = 1,
    double speedBytesPerSecond = 0,
    int currentIndex = 0,
  }) async {
    await _invoke('start', <String, Object>{""",
    """  Future<void> start({
    required String taskId,
    required String displayName,
    double progress = 0.0,
    int totalBytes = -1,
    int transferredBytes = 0,
    int completedCount = 0,
    int batchTotal = 1,
    double speedBytesPerSecond = 0,
    int currentIndex = 0,
  }) async {
    _cancelPendingUpdate();
    _lastUpdateAt = DateTime.now();
    await _invoke('start', <String, Object>{""",
)
replace_once(
    continued,
    """  Future<void> update({
    required String taskId,
    required double progress,
    required int totalBytes,
    int transferredBytes = 0,
    int completedCount = 0,
    int batchTotal = 1,
    double speedBytesPerSecond = 0,
    String displayName = '',
    int currentIndex = 0,
  }) async {
    await _invoke('update', <String, Object>{
      'taskId': taskId,
      'progress': progress.clamp(0.0, 1.0).toDouble(),
      'totalBytes': totalBytes,
      'transferredBytes': transferredBytes,
      'completedCount': completedCount,
      'batchTotal': batchTotal,
      'speedBytesPerSecond': speedBytesPerSecond,
      if (displayName.isNotEmpty) 'displayName': displayName,
      'currentIndex': currentIndex,
    });
  }""",
    """  Future<void> update({
    required String taskId,
    required double progress,
    required int totalBytes,
    int transferredBytes = 0,
    int completedCount = 0,
    int batchTotal = 1,
    double speedBytesPerSecond = 0,
    String displayName = '',
    int currentIndex = 0,
  }) async {
    await _queueUpdate(<String, Object>{
      'taskId': taskId,
      'progress': progress.clamp(0.0, 1.0).toDouble(),
      'totalBytes': totalBytes,
      'transferredBytes': transferredBytes,
      'completedCount': completedCount,
      'batchTotal': batchTotal,
      'speedBytesPerSecond': speedBytesPerSecond,
      if (displayName.isNotEmpty) 'displayName': displayName,
      'currentIndex': currentIndex,
    });
  }

  Future<void> _queueUpdate(Map<String, Object> arguments) async {
    if (!_isAvailable) return;
    _pendingUpdate = arguments;
    final now = DateTime.now();
    final last = _lastUpdateAt;
    if (last == null || now.difference(last) >= _updateSampleInterval) {
      _updateTimer?.cancel();
      _updateTimer = null;
      final pending = _pendingUpdate;
      _pendingUpdate = null;
      _lastUpdateAt = now;
      if (pending != null) await _invoke('update', pending);
      return;
    }

    final delay = _updateSampleInterval - now.difference(last);
    _updateTimer ??= Timer(delay, () async {
      _updateTimer = null;
      final pending = _pendingUpdate;
      _pendingUpdate = null;
      if (pending == null || !_isAvailable) return;
      _lastUpdateAt = DateTime.now();
      await _invoke('update', pending);
    });
  }

  void _cancelPendingUpdate() {
    _updateTimer?.cancel();
    _updateTimer = null;
    _pendingUpdate = null;
  }""",
)
replace_once(
    continued,
    """  }) async {
    await _invoke('finish', <String, Object>{
      'taskId': taskId,""",
    """  }) async {
    _cancelPendingUpdate();
    await _invoke('finish', <String, Object>{
      'taskId': taskId,""",
)
replace_once(
    continued,
    """  Future<void> stop({required String taskId, bool endSession = false}) async {
    await _invoke('stop', <String, Object>{""",
    """  Future<void> stop({required String taskId, bool endSession = false}) async {
    _cancelPendingUpdate();
    await _invoke('stop', <String, Object>{""",
)
replace_once(
    continued,
    """  Future<void> dispose() async {
    if (_handlerInstalled) {""",
    """  Future<void> dispose() async {
    _cancelPendingUpdate();
    if (_handlerInstalled) {""",
)

diagnostic = "lib/core/services/download_diagnostic_log.dart"
replace_once(
    diagnostic,
    """  int _rotation = 0;
  int _bytes = 0, _sequence = 0, _pending = 0, _dropped = 0;
  final String _session = '${DateTime.now().microsecondsSinceEpoch}-$pid';""",
    """  int _rotation = 0;
  int _bytes = 0, _sequence = 0, _pending = 0, _dropped = 0;
  final String _session = '${DateTime.now().microsecondsSinceEpoch}-$pid';
  static const Duration _highFrequencySampleInterval = Duration(seconds: 1);
  final Map<String, DateTime> _lastHighFrequencyEventAt = <String, DateTime>{};""",
)
replace_once(
    diagnostic,
    """    enabled = false;
    await flush();
    if (value) {""",
    """    enabled = false;
    await flush();
    _lastHighFrequencyEventAt.clear();
    if (value) {""",
)
replace_once(
    diagnostic,
    """  void record(String event, [Map<String, Object?> fields = const {}]) {
    if (!enabled) return;
    if (_pending >= maxPending) {""",
    """  void record(String event, [Map<String, Object?> fields = const {}]) {
    if (!enabled) return;
    if (_suppressHighFrequencyProgress(event, fields)) return;
    if (_pending >= maxPending) {""",
)
replace_once(
    diagnostic,
    """  Future<void> flush() => _tail;""",
    """  bool _suppressHighFrequencyProgress(
    String event,
    Map<String, Object?> fields,
  ) {
    final highFrequency =
        event == 'native.progress' ||
        event == 'chunk.update' ||
        (event == 'task.update' && fields.containsKey('progress'));
    if (!highFrequency) return false;

    final taskId = fields['taskId']?.toString() ?? '';
    if (taskId.isEmpty) return false;
    final terminal =
        fields['result'] == true ||
        fields['status'] != null ||
        fields['errorType'] != null ||
        fields['httpStatus'] != null;
    if (terminal) {
      _lastHighFrequencyEventAt.removeWhere(
        (key, _) => key.endsWith(':$taskId'),
      );
      return false;
    }

    final key = '$event:$taskId';
    final now = DateTime.now();
    final previous = _lastHighFrequencyEventAt[key];
    if (previous != null &&
        now.difference(previous) < _highFrequencySampleInterval) {
      return true;
    }
    _lastHighFrequencyEventAt[key] = now;
    return false;
  }

  Future<void> flush() => _tail;""",
)

runtime_test = "test/core/services/download_runtime_stability_review_test.dart"
replace_once(
    runtime_test,
    """    test('continued-processing speed zero explicitly clears stale speed', () {
      final swift = File('ios/Runner/DownloadContinuedProcessingManager.swift')
          .readAsStringSync();
      expect(swift, contains('speedBytesPerSecond >= 0'));
    });""",
    """    test('continued-processing speed zero explicitly clears stale speed', () {
      final swift = File('ios/Runner/DownloadContinuedProcessingManager.swift')
          .readAsStringSync();
      expect(swift, contains('speedBytesPerSecond >= 0'));
    });

    test('multipart progress callback cannot feed native ingress back into itself', () {
      final source = File('lib/core/services/download_service.dart')
          .readAsStringSync();
      final start = source.indexOf('onPartProgress: (parent, child, progress) {');
      final end = source.indexOf('onHostPressure:', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final callback = source.substring(start, end);
      expect(callback, contains('_publishChunkProgress('));
      expect(callback, isNot(contains('_handleNativeChunkUpdate(')));
      expect(source, contains('void _publishChunkProgress({'));
    });

    test('continued-processing metric updates are coalesced to one per second', () {
      final source = File(
        'lib/core/services/download_continued_processing_service.dart',
      ).readAsStringSync();
      expect(
        source,
        contains('_updateSampleInterval = Duration(seconds: 1)'),
      );
      expect(source, contains('Future<void> _queueUpdate('));
      expect(source, contains('_pendingUpdate = arguments'));
      expect(source, contains('_cancelPendingUpdate();'));
    });""",
)

Path("test/core/services/download_diagnostic_log_test.dart").write_text(
    r"""import 'dart:convert';
import 'dart:io';

import 'package:animewitcher/core/services/download_diagnostic_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('samples hot progress but never suppresses a terminal event', () async {
    final directory = await Directory.systemTemp.createTemp(
      'animewitcher-download-log-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final log = DownloadDiagnosticLog(() async => directory);
    await log.configure(true);
    log.record('chunk.update', {
      'taskId': 'episode.part.0',
      'progress': 0.1,
    });
    log.record('chunk.update', {
      'taskId': 'episode.part.0',
      'progress': 0.2,
    });
    log.record('chunk.update', {
      'taskId': 'episode.part.0',
      'progress': 0.3,
    });
    log.record('chunk.update', {
      'taskId': 'episode.part.0',
      'progress': 1.0,
      'result': true,
    });
    await log.flush();

    final rows = <Map<String, dynamic>>[];
    for (final file in await log.listFiles()) {
      for (final line in await file.readAsLines()) {
        final decoded = jsonDecode(line);
        if (decoded is Map) rows.add(Map<String, dynamic>.from(decoded));
      }
    }
    final progressRows = rows
        .where((row) => row['event'] == 'chunk.update')
        .toList(growable: false);
    expect(progressRows, hasLength(2));
    expect(progressRows.first['progress'], 0.1);
    expect(progressRows.last['result'], isTrue);
  });
}
"""
)
