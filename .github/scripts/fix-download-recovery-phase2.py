from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match, found {count}\n--- needle ---\n{old}")
    p.write_text(text.replace(old, new, 1))


parallel = "lib/core/services/persistent_parallel_download.dart"
range_transfer = "lib/core/services/download_range_transfer.dart"
fast_fail_test = "test/core/services/download_range_fast_fail_policy_test.dart"
fallback_test = "test/core/services/persistent_parallel_download_fallback_test.dart"

# Phase 2A: only train the adaptive response timeout from a response that
# actually satisfies the Range request. Fast 4xx/5xx/malformed responses must
# not shrink a later healthy request to the three-second floor.
replace_once(
    range_transfer,
    "bool shouldEmitDownloadRangeProgress({\n",
    "bool shouldRememberDownloadRangeConnectTime({\n"
    "  required int? statusCode,\n"
    "  required String? requestedRange,\n"
    "  required String? contentRange,\n"
    "}) {\n"
    "  if (statusCode != 206 || requestedRange == null || contentRange == null) {\n"
    "    return false;\n"
    "  }\n"
    "  final request = RegExp(r'^bytes=(\\d+)-(\\d*)\\$')\n"
    "      .firstMatch(requestedRange.trim().toLowerCase());\n"
    "  final response = RegExp(r'^bytes (\\d+)-(\\d+)/(\\d+)\\$')\n"
    "      .firstMatch(contentRange.trim().toLowerCase());\n"
    "  if (request == null || response == null) return false;\n"
    "\n"
    "  final requestStart = int.parse(request[1]!);\n"
    "  final requestEndText = request[2]!;\n"
    "  final responseStart = int.parse(response[1]!);\n"
    "  final responseEnd = int.parse(response[2]!);\n"
    "  final resourceSize = int.parse(response[3]!);\n"
    "  if (responseStart != requestStart ||\n"
    "      responseEnd < responseStart ||\n"
    "      resourceSize <= responseEnd) {\n"
    "    return false;\n"
    "  }\n"
    "  if (requestEndText.isNotEmpty && responseEnd != int.parse(requestEndText)) {\n"
    "    return false;\n"
    "  }\n"
    "  return true;\n"
    "}\n\n"
    "bool shouldEmitDownloadRangeProgress({\n",
)

replace_once(
    range_transfer,
    "      _rememberConnectTime(url, clock.elapsed);\n      return response;\n",
    "      String? requestedRange;\n"
    "      for (final entry in headers.entries) {\n"
    "        if (entry.key.toLowerCase() == 'range') {\n"
    "          requestedRange = entry.value;\n"
    "          break;\n"
    "        }\n"
    "      }\n"
    "      if (shouldRememberDownloadRangeConnectTime(\n"
    "        statusCode: response.statusCode,\n"
    "        requestedRange: requestedRange,\n"
    "        contentRange: response.headers.value('content-range'),\n"
    "      )) {\n"
    "        _rememberConnectTime(url, clock.elapsed);\n"
    "      }\n"
    "      return response;\n",
)

# Phase 2B: make the multipart snapshot carry the resource validator and pin it
# across all later/relaunched children. This prevents assembly from mixing byte
# ranges from two different ETag/Last-Modified generations.
replace_once(
    parallel,
    "/// contained only `parts`. Version 2 also records the logical generation and\n"
    "/// expected byte count so a process relaunch cannot silently combine a torn\n"
    "/// checkpoint with incompatible recovery metadata.\n"
    "const int kParallelManifestSchemaVersion = 2;\n",
    "/// contained only `parts`. Version 2 added logical generation/expected byte\n"
    "/// identity. Version 3 also pins the first strong ETag (or Last-Modified)\n"
    "/// observed from a validated child response, so later/relaunched ranges\n"
    "/// cannot silently assemble bytes from a different resource generation.\n"
    "const int kParallelManifestSchemaVersion = 3;\n\n"
    "/// Validate response metadata from a native multipart child. A full HTTP\n"
    "/// 200 is safe only when this child already represents the entire resource;\n"
    "/// multi-part ignored-Range responses are handled by the full-body fallback.\n"
    "/// For HTTP 206 the final byte and total resource size must match the\n"
    "/// immutable manifest Range. The response start may be inside the Range\n"
    "/// because URLSession resumeData can restart from an already durable prefix.\n"
    "bool downloadPartResponseMatchesRequestedRange({\n"
    "  required int from,\n"
    "  required int to,\n"
    "  required int resourceSize,\n"
    "  required int? statusCode,\n"
    "  required Map<String, String>? responseHeaders,\n"
    "}) {\n"
    "  // Older platform/plugin updates did not always expose final response\n"
    "  // metadata. Preserve compatibility there; current background_downloader\n"
    "  // supplies response headers/status for successful final states.\n"
    "  if (statusCode == null && responseHeaders == null) return true;\n"
    "  if (statusCode == 200) return from == 0 && to == resourceSize - 1;\n"
    "  if (statusCode != 206 || responseHeaders == null) return false;\n"
    "\n"
    "  String? contentRange;\n"
    "  for (final entry in responseHeaders.entries) {\n"
    "    if (entry.key.toLowerCase() == 'content-range') {\n"
    "      contentRange = entry.value.trim().toLowerCase();\n"
    "      break;\n"
    "    }\n"
    "  }\n"
    "  final match = RegExp(r'^bytes (\\d+)-(\\d+)/(\\d+)\\$')\n"
    "      .firstMatch(contentRange ?? '');\n"
    "  if (match == null) return false;\n"
    "  final responseStart = int.parse(match[1]!);\n"
    "  final responseEnd = int.parse(match[2]!);\n"
    "  final responseSize = int.parse(match[3]!);\n"
    "  return responseStart >= from &&\n"
    "      responseStart <= to &&\n"
    "      responseEnd == to &&\n"
    "      responseSize == resourceSize;\n"
    "}\n",
)

replace_once(
    parallel,
    "        final session = _ParallelSession(\n"
    "          task,\n"
    "          manifest,\n"
    "          parts,\n"
    "          generation: savedGeneration,\n"
    "        );\n"
    "        _register(session);\n",
    "        final savedValidator = json['resourceValidator'] is String\n"
    "            ? (json['resourceValidator'] as String).trim()\n"
    "            : '';\n"
    "        final session = _ParallelSession(\n"
    "          task,\n"
    "          manifest,\n"
    "          parts,\n"
    "          generation: savedGeneration,\n"
    "          resourceValidator: savedValidator.isEmpty ? null : savedValidator,\n"
    "        );\n"
    "        _applyPinnedValidatorToPendingParts(session);\n"
    "        _register(session);\n",
)

replace_once(
    parallel,
    "        childHeaders['Range'] = 'bytes=${part.from}-${part.to}';\n"
    "        childHeaders['Accept-Encoding'] = 'identity';\n"
    "        part.task = part.task.copyWith(\n",
    "        childHeaders['Range'] = 'bytes=${part.from}-${part.to}';\n"
    "        childHeaders['Accept-Encoding'] = 'identity';\n"
    "        final validator = session.resourceValidator;\n"
    "        if (validator != null) childHeaders['If-Range'] = validator;\n"
    "        part.task = part.task.copyWith(\n",
)

replace_once(
    parallel,
    "      'expectedBytes': session.size,\n"
    "      'parts': session.parts.map((part) => part.toJson()).toList(),\n",
    "      'expectedBytes': session.size,\n"
    "      'resourceValidator': session.resourceValidator,\n"
    "      'parts': session.parts.map((part) => part.toJson()).toList(),\n",
)

replace_once(
    parallel,
    "  Future<bool> _adoptIgnoredRangeFullBody(\n",
    "  String? _responseIfRangeValidator(Map<String, String>? headers) {\n"
    "    if (headers == null || headers.isEmpty) return null;\n"
    "    String? etag;\n"
    "    String? lastModified;\n"
    "    for (final entry in headers.entries) {\n"
    "      switch (entry.key.toLowerCase()) {\n"
    "        case 'etag':\n"
    "          etag = entry.value.trim();\n"
    "        case 'last-modified':\n"
    "          lastModified = entry.value.trim();\n"
    "      }\n"
    "    }\n"
    "    if (etag != null &&\n"
    "        etag!.isNotEmpty &&\n"
    "        !etag!.toLowerCase().startsWith('w/')) {\n"
    "      return etag;\n"
    "    }\n"
    "    if (lastModified != null && lastModified!.isNotEmpty) {\n"
    "      return lastModified;\n"
    "    }\n"
    "    return null;\n"
    "  }\n\n"
    "  void _applyPinnedValidatorToPendingParts(_ParallelSession session) {\n"
    "    final validator = session.resourceValidator;\n"
    "    if (validator == null || validator.isEmpty) return;\n"
    "    for (final part in session.parts) {\n"
    "      if (part.complete) continue;\n"
    "      final headers = Map<String, String>.from(part.task.headers)\n"
    "        ..removeWhere((key, _) => key.toLowerCase() == 'if-range');\n"
    "      headers['If-Range'] = validator;\n"
    "      part.task = part.task.copyWith(headers: headers);\n"
    "    }\n"
    "  }\n\n"
    "  Future<void> _invalidateCompletedRange(\n"
    "    _ParallelSession session,\n"
    "    _DownloadPart part, {\n"
    "    required String reason,\n"
    "  }) async {\n"
    "    diagnosticLog?.record('parallel.rangeRejected', {\n"
    "      'taskId': session.task.taskId,\n"
    "      'childTaskId': part.task.taskId,\n"
    "      'reason': reason,\n"
    "    });\n"
    "    _cancelTailStallWatch(part);\n"
    "    part.recoveryTimer?.cancel();\n"
    "    part.recoveryTimer = null;\n"
    "    session.currentBatchPendingIds.remove(part.task.taskId);\n"
    "    _activeConnectionIds.remove(part.task.taskId);\n"
    "    part.launched = false;\n"
    "    part.complete = false;\n"
    "    part.progress = 0;\n"
    "    part.credibleProgress = 0;\n"
    "    part.speed = 0;\n"
    "    part.recoveryAttempts = 0;\n"
    "    part.tailRecoveryAttempted = false;\n"
    "    part.tailWatchProgress = -1;\n"
    "    part.lastNativeBridgeBytes = 0;\n"
    "    part.lastNativeBridgeAt = null;\n"
    "    final file = File(await part.task.filePath());\n"
    "    try {\n"
    "      if (await file.exists()) await file.delete();\n"
    "    } catch (_) {}\n"
    "    await saveRecord(\n"
    "      TaskRecord(part.task, TaskStatus.paused, 0, part.size),\n"
    "    );\n"
    "    onPartProgress(session.task.taskId, part.task.taskId, 0);\n"
    "    await _persist(session);\n"
    "  }\n\n"
    "  Future<bool> _validateCompletedNativeRange(\n"
    "    _ParallelSession session,\n"
    "    _DownloadPart part,\n"
    "    TaskStatusUpdate update,\n"
    "  ) async {\n"
    "    if (!downloadPartResponseMatchesRequestedRange(\n"
    "      from: part.from,\n"
    "      to: part.to,\n"
    "      resourceSize: session.size,\n"
    "      statusCode: update.responseStatusCode,\n"
    "      responseHeaders: update.responseHeaders,\n"
    "    )) {\n"
    "      await _invalidateCompletedRange(\n"
    "        session,\n"
    "        part,\n"
    "        reason: 'contentRangeMismatch',\n"
    "      );\n"
    "      await _pause(session);\n"
    "      return false;\n"
    "    }\n"
    "\n"
    "    final observedValidator = _responseIfRangeValidator(update.responseHeaders);\n"
    "    if (observedValidator == null) return true;\n"
    "    final pinned = session.resourceValidator;\n"
    "    if (pinned == null) {\n"
    "      session.resourceValidator = observedValidator;\n"
    "      _applyPinnedValidatorToPendingParts(session);\n"
    "      return true;\n"
    "    }\n"
    "    if (pinned == observedValidator) return true;\n"
    "\n"
    "    await _invalidateCompletedRange(\n"
    "      session,\n"
    "      part,\n"
    "      reason: 'resourceValidatorChanged',\n"
    "    );\n"
    "    await _pause(session);\n"
    "    return false;\n"
    "  }\n\n"
    "  Future<bool> _adoptIgnoredRangeFullBody(\n",
)

replace_once(
    parallel,
    "            if (!exists || length != part.size) {\n"
    "              // A completed callback with the wrong durable byte count is a\n"
    "              // data-integrity boundary, not a coordinator race. Keep the\n"
    "              // bytes for diagnosis/resume and park the parent deterministically.\n"
    "              await _pause(session);\n"
    "              return;\n"
    "            }\n"
    "            _markConnectionReady(session, part);\n",
    "            if (!exists || length != part.size) {\n"
    "              // A completed callback with the wrong durable byte count is a\n"
    "              // data-integrity boundary, not a coordinator race. Keep the\n"
    "              // bytes for diagnosis/resume and park the parent deterministically.\n"
    "              await _pause(session);\n"
    "              return;\n"
    "            }\n"
    "            if (!await _validateCompletedNativeRange(session, part, update)) {\n"
    "              return;\n"
    "            }\n"
    "            _markConnectionReady(session, part);\n",
)

replace_once(
    parallel,
    "class _ParallelSession {\n"
    "  _ParallelSession(this.task, this.manifest, this.parts, {this.generation = 0});\n\n"
    "  ParallelDownloadTask task;\n"
    "  final File manifest;\n"
    "  final List<_DownloadPart> parts;\n"
    "  bool active = false;\n"
    "  bool deleted = false;\n"
    "  int generation;\n",
    "class _ParallelSession {\n"
    "  _ParallelSession(\n"
    "    this.task,\n"
    "    this.manifest,\n"
    "    this.parts, {\n"
    "    this.generation = 0,\n"
    "    this.resourceValidator,\n"
    "  });\n\n"
    "  ParallelDownloadTask task;\n"
    "  final File manifest;\n"
    "  final List<_DownloadPart> parts;\n"
    "  bool active = false;\n"
    "  bool deleted = false;\n"
    "  int generation;\n"
    "  String? resourceValidator;\n",
)

# Unit tests for timeout-baseline poisoning.
p = Path(fast_fail_test)
text = p.read_text()
needle = "  test('never becomes less tolerant than the previous thirty-second ceiling', () {"
if needle not in text:
    raise SystemExit(f"{fast_fail_test}: insertion point missing")
insert = """  test('only validated HTTP 206 ranges train the fast-fail baseline', () {
    expect(
      shouldRememberDownloadRangeConnectTime(
        statusCode: 503,
        requestedRange: 'bytes=100-199',
        contentRange: null,
      ),
      isFalse,
    );
    expect(
      shouldRememberDownloadRangeConnectTime(
        statusCode: 206,
        requestedRange: 'bytes=100-199',
        contentRange: 'bytes 100-199/1000',
      ),
      isTrue,
    );
    expect(
      shouldRememberDownloadRangeConnectTime(
        statusCode: 206,
        requestedRange: 'bytes=100-199',
        contentRange: 'bytes 101-200/1000',
      ),
      isFalse,
    );
    expect(
      shouldRememberDownloadRangeConnectTime(
        statusCode: 200,
        requestedRange: 'bytes=100-',
        contentRange: null,
      ),
      isFalse,
    );
  });

"""
p.write_text(text.replace(needle, insert + needle, 1))

# Behavioral tests for final native Content-Range validation and validator pinning.
p = Path(fallback_test)
text = p.read_text()
if not text.endswith("}\n"):
    raise SystemExit(f"{fallback_test}: unexpected file ending")
text = text[:-2]
text += r'''

  test('rejects exact-size child bytes when native Content-Range is wrong', () async {
    final directory = await Directory.systemTemp.createTemp(
      'parallel-content-range-mismatch-',
    );
    final parent = ParallelDownloadTask(
      taskId: 'episode-range-mismatch',
      url: 'https://example.com/video',
      filename: 'video.mp4',
      directory: directory.path,
      baseDirectory: BaseDirectory.root,
      chunks: 4,
      allowPause: true,
    );
    final records = <String, TaskRecord>{};
    final starts = <DownloadTask>[];
    final coordinator = PersistentParallelDownload(
      startPart: (task, progress, size) async {
        starts.add(task);
        return true;
      },
      pausePart: (_) async {},
      cancelParts: (_) async {},
      saveRecord: (record) async => records[record.task.taskId] = record,
      recordForId: (id) async => records[id],
      onUpdate: (_) {},
      onPartProgress: (_, _, _) {},
    );

    try {
      expect(await coordinator.start(parent, 20), isTrue);
      final first = starts.single;
      final child = File(await first.filePath());
      await child.parent.create(recursive: true);
      await child.writeAsBytes(List<int>.filled(5, 7), flush: true);

      coordinator.handleUpdate(
        TaskStatusUpdate(first, TaskStatus.complete).copyWith(
          responseStatusCode: 206,
          responseHeaders: const {
            'content-range': 'bytes 5-9/20',
            'etag': '"v1"',
          },
        ),
      );
      await waitUntil(
        () => records[parent.taskId]?.status == TaskStatus.paused,
      );

      expect(await child.exists(), isFalse);
      expect(await File(await parent.filePath()).exists(), isFalse);
      expect(records[first.taskId]?.progress, 0);
    } finally {
      await coordinator.dispose();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });

  test('pins first validator onto later ranges and rejects a changed entity', () async {
    final directory = await Directory.systemTemp.createTemp(
      'parallel-validator-pin-',
    );
    final parent = ParallelDownloadTask(
      taskId: 'episode-validator-pin',
      url: 'https://example.com/video',
      filename: 'video.mp4',
      directory: directory.path,
      baseDirectory: BaseDirectory.root,
      chunks: 4,
      allowPause: true,
    );
    final records = <String, TaskRecord>{};
    final starts = <DownloadTask>[];
    final coordinator = PersistentParallelDownload(
      startPart: (task, progress, size) async {
        starts.add(task);
        return true;
      },
      pausePart: (_) async {},
      cancelParts: (_) async {},
      saveRecord: (record) async => records[record.task.taskId] = record,
      recordForId: (id) async => records[id],
      onUpdate: (_) {},
      onPartProgress: (_, _, _) {},
    );

    try {
      expect(await coordinator.start(parent, 20), isTrue);
      final first = starts.single;
      final firstFile = File(await first.filePath());
      await firstFile.parent.create(recursive: true);
      await firstFile.writeAsBytes(List<int>.filled(5, 1), flush: true);
      coordinator.handleUpdate(
        TaskStatusUpdate(first, TaskStatus.complete).copyWith(
          responseStatusCode: 206,
          responseHeaders: const {
            'content-range': 'bytes 0-4/20',
            'etag': '"v1"',
          },
        ),
      );

      await waitUntil(() => starts.length >= 3);
      expect(starts[1].headers['If-Range'], '"v1"');
      expect(starts[2].headers['If-Range'], '"v1"');

      final second = starts[1];
      expect(second.headers['Range'], 'bytes=5-9');
      final secondFile = File(await second.filePath());
      await secondFile.parent.create(recursive: true);
      await secondFile.writeAsBytes(List<int>.filled(5, 2), flush: true);
      coordinator.handleUpdate(
        TaskStatusUpdate(second, TaskStatus.complete).copyWith(
          responseStatusCode: 206,
          responseHeaders: const {
            'content-range': 'bytes 5-9/20',
            'etag': '"v2"',
          },
        ),
      );

      await waitUntil(
        () => records[parent.taskId]?.status == TaskStatus.paused,
      );
      expect(await firstFile.exists(), isTrue);
      expect(await secondFile.exists(), isFalse);
      expect(records[second.taskId]?.progress, 0);

      final manifest = File('${await parent.filePath()}.parts/manifest.json');
      final manifestText = await manifest.readAsString();
      expect(manifestText, contains('\\"resourceValidator\\":\\"\\\\\\"v1\\\\\\"\\"'));
    } finally {
      await coordinator.dispose();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });
}
'''
p.write_text(text)

print('Applied download recovery phase 2: Range integrity, validator pinning, and timeout baseline hardening.')
