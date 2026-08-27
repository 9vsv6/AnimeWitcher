import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'stale_connection_retry.dart';

part 'dio_client_provider.g.dart';

@riverpod
Dio dioClient(Ref ref) => createAnimeWitcherDio();
