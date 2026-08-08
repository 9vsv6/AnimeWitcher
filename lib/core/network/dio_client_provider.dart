import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'http_defaults.dart';

part 'dio_client_provider.g.dart';

@riverpod
Dio dioClient(Ref ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      // Default to a real browser UA so resolution presents the same
      // identity the player will use during playback. Per-request headers
      // from plugins still override this. See http_defaults.dart.
      headers: const {'User-Agent': kDefaultBrowserUserAgent},
    ),
  );

  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.idleTimeout = const Duration(minutes: 5);
      client.maxConnectionsPerHost = 10;
      return client;
    },
  );

  return dio;
}
