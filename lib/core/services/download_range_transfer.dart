import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// A cancellable append. Starting returns after the response is validated,
/// leaving the download service's control queue free for pause/cancel.
class DownloadRangeTransfer {
  DownloadRangeTransfer(this.dio);
  final Dio dio;
  final _operations = <String, _RangeOperation>{};
  bool isActive(String id) => _operations.containsKey(id);

  Future<void> stop(String id) async {
    final operation = _operations[id];
    if (operation == null) return;
    operation.token.cancel('Download stopped');
    await operation.done.future;
  }

  void dispose() {
    for (final operation in _operations.values) {
      operation.token.cancel('Service disposed');
    }
  }

  Future<bool> start({
    required String id,
    required String url,
    required Map<String, String> headers,
    required File file,
    required int existingBytes,
    required int expectedBytes,
    required Future<void> Function(int written, int total, bool complete)
    onState,
    required Future<void> Function(int written, int total) onPaused,
  }) async {
    if (_operations.containsKey(id)) return true;
    final operation = _RangeOperation();
    _operations[id] = operation;
    var launched = false;
    Stream<List<int>>? stream;
    try {
      final bounded = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(
        headers.entries
                .where((entry) => entry.key.toLowerCase() == 'range')
                .map((entry) => entry.value)
                .firstOrNull ??
            '',
      );
      final origin = bounded == null ? 0 : int.parse(bounded[1]!);
      final limit = bounded == null ? null : int.parse(bounded[2]!);
      final start = origin + existingBytes;
      final requestHeaders = Map<String, String>.from(headers)
        ..removeWhere((key, _) => key.toLowerCase() == 'range');
      requestHeaders['Range'] = 'bytes=$start-${limit ?? ''}';
      requestHeaders['Accept-Encoding'] = 'identity';
      final response = await dio
          .get<ResponseBody>(
            url,
            cancelToken: operation.token,
            options: Options(
              headers: requestHeaders,
              responseType: ResponseType.stream,
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 15),
              validateStatus: (_) => true,
            ),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              operation.token.cancel('Response timeout');
              throw TimeoutException('Response timeout');
            },
          );
      stream = response.data?.stream;
      final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
          .firstMatch(response.headers.value('content-range') ?? '');
      if (response.statusCode != 206 ||
          range == null ||
          int.parse(range[1]!) != start ||
          stream == null)
        return false;
      final end = int.parse(range[2]!);
      final resourceSize = int.parse(range[3]!);
      final total = limit == null ? resourceSize : limit - origin + 1;
      if (end < start ||
          end >= resourceSize ||
          end != (limit ?? resourceSize - 1) ||
          (expectedBytes > 0 && total != expectedBytes))
        return false;
      if (!await file.exists() || await file.length() != existingBytes)
        return false;
      launched = true;
      unawaited(
        _receive(
          id,
          operation,
          file,
          stream,
          existingBytes,
          total,
          onState,
          onPaused,
        ),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      if (!launched) {
        operation.token.cancel();
        if (stream != null) await stream.listen(null).cancel();
        _operations.remove(id);
        operation.done.complete();
      }
    }
  }

  Future<void> _receive(
    String id,
    _RangeOperation operation,
    File file,
    Stream<List<int>> stream,
    int written,
    int total,
    Future<void> Function(int, int, bool) onState,
    Future<void> Function(int, int) onPaused,
  ) async {
    RandomAccessFile? output;
    var complete = false;
    try {
      output = await file.open(mode: FileMode.append);
      await for (final bytes in stream.timeout(const Duration(seconds: 30))) {
        if (operation.token.isCancelled) break;
        if (written + bytes.length > total)
          throw const FormatException('Range body is too long');
        await output.writeFrom(bytes);
        written += bytes.length;
        await onState(written, total, false);
      }
      await output.flush();
      await output.close();
      output = null;
      if (written != total || operation.token.isCancelled)
        throw const FormatException('Range body is incomplete');
      await onState(written, total, true);
      complete = true;
    } catch (_) {
      // The onState(false) call retains the last durable offset. The caller
      // receives the final paused state after [stop] has joined this writer.
    } finally {
      await output?.close();
      operation.token.cancel();
      _operations.remove(id);
      try {
        if (!complete) await onPaused(written, total);
      } finally {
        operation.done.complete();
      }
    }
  }
}

class _RangeOperation {
  final token = CancelToken();
  final done = Completer<void>();
}
