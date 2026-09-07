import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// Keep retries short: a permanently dead episode must still yield its queue
/// slot, while transient CDN/radio failures should not force a manual resume.
const int kDownloadRangeRequestAttempts = 3;
const int kDownloadRangeReconnectAttempts = 2;
const Duration kDownloadRangeRetryBaseDelay = Duration(milliseconds: 250);

bool isRetryableDownloadHttpStatus(int? status) {
  if (status == null) return false;
  if (status == 408 || status == 425 || status == 429) return true;
  return status >= 500 && status <= 599;
}

Duration downloadRangeRetryDelay({
  required int retryIndex,
  String? retryAfter,
}) {
  final seconds = int.tryParse(retryAfter?.trim() ?? '');
  if (seconds != null && seconds >= 0) {
    return Duration(seconds: seconds.clamp(0, 30));
  }
  final shift = retryIndex.clamp(0, 4);
  return kDownloadRangeRetryBaseDelay * (1 << shift);
}

/// A cancellable append. Starting returns after the response is validated,
/// leaving the download service's control queue free for pause/cancel.
///
/// Gopeed treats every HTTP range connection as an independently recoverable
/// worker. This keeps AnimeWitcher's native/background architecture, but uses
/// the same principle for the Dart fallback path: if a response stream dies,
/// reconnect from the last durable byte instead of pausing the whole episode.
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
    _OpenedRange? opened;
    try {
      final spec = _RangeSpec.fromHeaders(headers);
      if (!await file.exists() || await file.length() != existingBytes) {
        return false;
      }
      opened = await _openWithRetries(
        operation: operation,
        url: url,
        headers: headers,
        spec: spec,
        written: existingBytes,
        expectedBytes: expectedBytes,
        attempts: kDownloadRangeRequestAttempts,
      );
      if (opened == null) return false;
      launched = true;
      unawaited(
        _receive(
          id: id,
          operation: operation,
          url: url,
          headers: headers,
          spec: spec,
          file: file,
          opened: opened,
          written: existingBytes,
          expectedBytes: expectedBytes,
          onState: onState,
          onPaused: onPaused,
        ),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      if (!launched) {
        operation.token.cancel();
        await _discard(opened?.stream);
        _operations.remove(id);
        if (!operation.done.isCompleted) operation.done.complete();
      }
    }
  }

  Future<_OpenedRange?> _openWithRetries({
    required _RangeOperation operation,
    required String url,
    required Map<String, String> headers,
    required _RangeSpec spec,
    required int written,
    required int expectedBytes,
    required int attempts,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (operation.token.isCancelled) return null;
      Response<ResponseBody>? response;
      Stream<List<int>>? stream;
      try {
        final start = spec.origin + written;
        final requestHeaders = Map<String, String>.from(headers)
          ..removeWhere((key, _) => key.toLowerCase() == 'range');
        requestHeaders['Range'] = 'bytes=$start-${spec.limit ?? ''}';
        requestHeaders['Accept-Encoding'] = 'identity';
        response = await dio
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
                throw TimeoutException('Response timeout');
              },
            );
        stream = response.data?.stream;
        final status = response.statusCode;
        if (isRetryableDownloadHttpStatus(status)) {
          await _discard(stream);
          if (attempt + 1 >= attempts) return null;
          await Future<void>.delayed(
            downloadRangeRetryDelay(
              retryIndex: attempt,
              retryAfter: response.headers.value('retry-after'),
            ),
          );
          continue;
        }

        final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
            .firstMatch(response.headers.value('content-range') ?? '');
        if (status != 206 || range == null || stream == null) {
          await _discard(stream);
          return null;
        }
        final responseStart = int.parse(range[1]!);
        final end = int.parse(range[2]!);
        final resourceSize = int.parse(range[3]!);
        final total = spec.limit == null
            ? resourceSize
            : spec.limit! - spec.origin + 1;
        if (responseStart != start ||
            end < start ||
            end >= resourceSize ||
            end != (spec.limit ?? resourceSize - 1) ||
            (expectedBytes > 0 && total != expectedBytes) ||
            written >= total) {
          await _discard(stream);
          return null;
        }
        return _OpenedRange(stream: stream, total: total);
      } catch (error) {
        await _discard(stream);
        if (operation.token.isCancelled ||
            !_isRetryableDownloadError(error) ||
            attempt + 1 >= attempts) {
          return null;
        }
        await Future<void>.delayed(
          downloadRangeRetryDelay(retryIndex: attempt),
        );
      }
    }
    return null;
  }

  bool _isRetryableDownloadError(Object error) {
    if (error is TimeoutException ||
        error is SocketException ||
        error is HttpException) {
      return true;
    }
    if (error is DioException) {
      if (error.type == DioExceptionType.cancel) return false;
      final status = error.response?.statusCode;
      if (isRetryableDownloadHttpStatus(status)) return true;
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
        case DioExceptionType.unknown:
          return true;
        case DioExceptionType.badCertificate:
        case DioExceptionType.badResponse:
        case DioExceptionType.cancel:
          return false;
      }
    }
    return false;
  }

  Future<void> _receive({
    required String id,
    required _RangeOperation operation,
    required String url,
    required Map<String, String> headers,
    required _RangeSpec spec,
    required File file,
    required _OpenedRange opened,
    required int written,
    required int expectedBytes,
    required Future<void> Function(int, int, bool) onState,
    required Future<void> Function(int, int) onPaused,
  }) async {
    RandomAccessFile? output;
    var complete = false;
    var current = opened;
    var reconnects = 0;
    final total = opened.total;
    try {
      output = await file.open(mode: FileMode.append);
      while (!operation.token.isCancelled && written < total) {
        Object? streamError;
        try {
          await for (final bytes in current.stream.timeout(
            const Duration(seconds: 30),
          )) {
            if (operation.token.isCancelled) break;
            if (written + bytes.length > total) {
              throw const FormatException('Range body is too long');
            }
            await output.writeFrom(bytes);
            written += bytes.length;
            await onState(written, total, false);
          }
        } catch (error) {
          streamError = error;
        }

        if (written == total && !operation.token.isCancelled) break;
        if (operation.token.isCancelled ||
            streamError is FormatException ||
            reconnects >= kDownloadRangeReconnectAttempts) {
          throw streamError ?? const FormatException('Range body is incomplete');
        }

        reconnects++;
        await output.flush();
        await Future<void>.delayed(
          downloadRangeRetryDelay(retryIndex: reconnects - 1),
        );
        final reopened = await _openWithRetries(
          operation: operation,
          url: url,
          headers: headers,
          spec: spec,
          written: written,
          expectedBytes: expectedBytes,
          attempts: 1,
        );
        if (reopened == null || reopened.total != total) {
          throw const FormatException('Could not reconnect range body');
        }
        current = reopened;
      }

      await output.flush();
      await output.close();
      output = null;
      if (written != total || operation.token.isCancelled) {
        throw const FormatException('Range body is incomplete');
      }
      await onState(written, total, true);
      complete = true;
    } catch (_) {
      // Keep every durable byte. The next explicit resume starts exactly from
      // [written] if the bounded automatic reconnects were exhausted.
    } finally {
      await output?.close();
      operation.token.cancel();
      _operations.remove(id);
      try {
        if (!complete) await onPaused(written, total);
      } finally {
        if (!operation.done.isCompleted) operation.done.complete();
      }
    }
  }

  Future<void> _discard(Stream<List<int>>? stream) async {
    if (stream == null) return;
    try {
      final subscription = stream.listen(null, onError: (_) {});
      await subscription.cancel();
    } catch (_) {}
  }
}

class _RangeSpec {
  const _RangeSpec(this.origin, this.limit);

  final int origin;
  final int? limit;

  factory _RangeSpec.fromHeaders(Map<String, String> headers) {
    final value = headers.entries
        .where((entry) => entry.key.toLowerCase() == 'range')
        .map((entry) => entry.value)
        .firstOrNull;
    final bounded = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(value ?? '');
    if (bounded == null) return const _RangeSpec(0, null);
    return _RangeSpec(int.parse(bounded[1]!), int.parse(bounded[2]!));
  }
}

class _OpenedRange {
  const _OpenedRange({required this.stream, required this.total});

  final Stream<List<int>> stream;
  final int total;
}

class _RangeOperation {
  final token = CancelToken();
  final done = Completer<void>();
}
