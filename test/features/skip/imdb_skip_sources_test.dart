import 'package:animewitcher/features/skip/data/imdb_skip_sources.dart';
import 'package:animewitcher/features/skip/data/skip_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

String _describe(List<SkipSegment> segments) => segments
    .map((s) => '${s.type.name} ${s.startTime}-${s.endTime}')
    .join(', ');

void main() {
  test('IntroDB.app: intro and credits in seconds, post-credits left out', () {
    // api.introdb.app/segments?imdb_id=tt2560140&season=1&episode=1
    final segments = parseIntroDbAppSegments(<String, dynamic>{
      'imdb_id': 'tt2560140',
      'intro': {
        'start_sec': 90,
        'end_sec': 150,
        'start_ms': 90000,
        'end_ms': 150000,
      },
      'recap': null,
      'outro': {'start_ms': 1434960, 'end_ms': 1524920},
      'post_credits': {'start_ms': 1525000, 'end_ms': 1560000},
    });
    expect(_describe(segments), 'intro 90.0-150.0, outro 1434.96-1524.92');
  });

  test('IntroDB.app: an open end runs to the end of the file', () {
    final segments = parseIntroDbAppSegments(<String, dynamic>{
      'outro': {'start_sec': 1400, 'end_sec': null},
    }, durationSec: 1440);
    expect(_describe(segments), 'outro 1400.0-1440.0');
  });

  test('SkipDB: segments in milliseconds, previews skip to the end', () {
    // api.skipdb.tv/api/segments?imdb_id=tt0903747&season=1&episode=1
    final segments = parseSkipDbSegments(<String, dynamic>{
      'imdb_id': 'tt0903747',
      'segments': {
        'intro': {'start_ms': 229500, 'end_ms': 246500, 'match': 'exact'},
        'recap': null,
        'outro': {'start_ms': 3434000, 'end_ms': 3500000, 'match': 'exact'},
        'preview': null,
      },
    });
    expect(_describe(segments), 'intro 229.5-246.5, outro 3434.0-3500.0');
  });

  test('SkipDB: a match made for a different cut is not used', () {
    final segments = parseSkipDbSegments(<String, dynamic>{
      'segments': {
        'intro': {'start_ms': 60000, 'end_ms': 150000, 'match': 'out-of-range'},
        'outro': {'start_ms': 1300000, 'end_ms': 1390000, 'match': 'shifted'},
      },
    });
    expect(_describe(segments), 'outro 1300.0-1390.0');
  });

  test('nothing is asked without an IMDb id', () async {
    var asked = 0;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            asked++;
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );
    final source = ImdbSkipSource(
      dio: dio,
      name: 'test',
      endpoint: 'https://example.invalid/segments',
      query: (id, season, episode, _) => {'imdb_id': id},
      parse: parseSkipDbSegments,
    );
    expect(await source.getSkipSegments(season: 1, episode: 1), isEmpty);
    expect(
      await source.getSkipSegments(imdbId: '12345', season: 1, episode: 1),
      isEmpty,
    );
    expect(asked, 0);
  });

  test(
    'SkipDB is asked with the stream length so it can fit the times',
    () async {
      Map<String, dynamic>? sent;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              sent = options.queryParameters;
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{
                    'segments': {
                      'intro': {
                        'start_ms': 90000,
                        'end_ms': 180000,
                        'match': 'exact',
                      },
                    },
                  },
                ),
              );
            },
          ),
        );
      final source = ImdbSkipSource(
        dio: dio,
        name: 'SkipDB',
        endpoint: 'https://api.skipdb.tv/api/segments',
        query: (id, season, episode, duration) => {
          'imdb_id': id,
          'season': season,
          'episode': episode,
          if (duration != null) 'duration': duration,
        },
        parse: parseSkipDbSegments,
      );
      final segments = await source.getSkipSegments(
        imdbId: 'tt2560140',
        season: 1,
        episode: 3,
        duration: 1440,
      );
      expect(sent, {
        'imdb_id': 'tt2560140',
        'season': 1,
        'episode': 3,
        'duration': 1440,
      });
      expect(_describe(segments), 'intro 90.0-180.0');
    },
  );
}
