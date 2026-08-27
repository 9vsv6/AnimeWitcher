import 'dart:io';
import 'dart:typed_data';

import 'package:animewitcher/core/network/stale_connection_retry.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailOnceAdapter implements HttpClientAdapter {
  int fetches = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetches += 1;
    if (fetches == 1) {
      throw const SocketException('Network is unreachable');
    }
    return ResponseBody.fromString(
      '{"hits":[]}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('connection errors after reconnect are stale network errors', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.connectionError,
      error: const SocketException('Network is unreachable'),
    );
    expect(isStaleNetworkError(error), isTrue);
  });

  test('HTTP 503 is not treated as a stale socket', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/'),
        statusCode: 503,
      ),
    );
    expect(isStaleNetworkError(error), isFalse);
  });

  test('a stale connection is retried once and then succeeds', () async {
    final adapter = _FailOnceAdapter();
    final dio = createAnimeWitcherDio(httpClientAdapter: adapter);

    final response = await dio.get<dynamic>('https://example.test/catalog');
    expect(adapter.fetches, 2);
    expect(response.statusCode, 200);
    expect(response.data, contains('hits'));
  });
}
