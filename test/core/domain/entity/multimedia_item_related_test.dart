import 'package:flutter_test/flutter_test.dart';
import 'package:animewitcher/core/domain/entity/multimedia_item.dart';

void main() {
  test('parses related items separately from recommendations', () {
    final item = MultimediaItem.fromJson({
      'title': 'Current Anime',
      'url': 'https://example.test/current',
      'posterUrl': 'https://example.test/current.jpg',
      'type': 'anime',
      'related': [
        {
          'title': 'Previous Season',
          'url': 'https://example.test/previous',
          'posterUrl': 'https://example.test/previous.jpg',
          'type': 'anime',
          'relationLabel': 'السابق',
          'relationType': 'PREQUEL',
        },
        {
          'title': 'The Movie',
          'url': 'https://example.test/movie',
          'posterUrl': 'https://example.test/movie.jpg',
          'type': 'movie',
          'relation_label': 'فيلم',
          'relation_type': 'SIDE_STORY',
        },
      ],
      'recommendations': [
        {
          'title': 'Similar Anime',
          'url': 'https://example.test/similar',
          'posterUrl': 'https://example.test/similar.jpg',
          'type': 'anime',
        },
      ],
    });

    expect(item.related, hasLength(2));
    expect(item.related!.first.relationLabel, 'السابق');
    expect(item.related!.first.relationType, 'PREQUEL');
    expect(item.related![1].contentType, MultimediaContentType.movie);
    expect(item.related![1].relationLabel, 'فيلم');
    expect(item.recommendations, hasLength(1));

    final roundTrip = MultimediaItem.fromJson(item.toJson());
    expect(roundTrip.related, hasLength(2));
    expect(roundTrip.related!.first.relationLabel, 'السابق');
    expect(roundTrip.related![1].relationType, 'SIDE_STORY');
    expect(roundTrip.recommendations, hasLength(1));
  });

  test('supports compatibility aliases from extensions', () {
    final item = MultimediaItem.fromJson({
      'title': 'Current Anime',
      'url': 'current',
      'posterUrl': 'current.jpg',
      'relations': [
        {
          'title': 'Next Season',
          'url': 'next',
          'posterUrl': 'next.jpg',
          'relationBadge': 'Next',
          'relation_type': 'SEQUEL',
        },
      ],
    });

    expect(item.related, hasLength(1));
    expect(item.related!.single.relationLabel, 'Next');
    expect(item.related!.single.relationType, 'SEQUEL');
  });

  test('ignores malformed nested related entries safely', () {
    final item = MultimediaItem.fromJson({
      'title': 'Current Anime',
      'url': 'current',
      'posterUrl': 'current.jpg',
      'related': [
        'invalid',
        {'title': 'Valid', 'url': 'valid', 'posterUrl': 'valid.jpg'},
      ],
    });

    expect(item.related, hasLength(1));
    expect(item.related!.single.title, 'Valid');
  });
}
