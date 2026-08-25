import 'package:flutter_test/flutter_test.dart';
import 'package:animewitcher/core/account/firestore_rest_client.dart';

void main() {
  group('FirestoreValueCodec', () {
    test('round-trips values used by account synchronization', () {
      final timestamp = DateTime.utc(2026, 8, 9, 12, 30);
      final source = <String, dynamic>{
        'name': 'AnimeWitcher',
        'watched': true,
        'position': 125000,
        'progress': 42.5,
        'date': timestamp,
        'episodes': <String>['ep-1', 'ep-2'],
        'settings': <String, dynamic>{'sync': true},
        'empty': null,
      };

      final decoded = FirestoreValueCodec.decodeFields(
        FirestoreValueCodec.encodeFields(source),
      );

      expect(decoded['name'], 'AnimeWitcher');
      expect(decoded['watched'], isTrue);
      expect(decoded['position'], 125000);
      expect(decoded['progress'], 42.5);
      expect(decoded['date'], timestamp);
      expect(decoded['episodes'], <String>['ep-1', 'ep-2']);
      expect(decoded['settings'], <String, dynamic>{'sync': true});
      expect(decoded['empty'], isNull);
    });

    test('encodes and decodes AnimeWitcher document references', () {
      final encoded = FirestoreValueCodec.encode(
        const FirestoreReference('anime_list/one_piece'),
      );

      expect(
        FirestoreValueCodec.decode(encoded),
        'anime_list/one_piece',
      );
    });

    test('keeps AnimeWitcher anime paths as string values', () {
      expect(
        FirestoreValueCodec.encode('anime_list/one_piece'),
        <String, dynamic>{'stringValue': 'anime_list/one_piece'},
      );
    });

    test('decodes a missing Firestore array as an empty list', () {
      expect(
        FirestoreValueCodec.decode(<String, dynamic>{
          'arrayValue': <String, dynamic>{},
        }),
        isEmpty,
      );
    });
  });
}
