import 'package:flutter_test/flutter_test.dart';
import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/core/utils/catalog_label.dart';

MultimediaItem _item({
  String type = 'مسلسل',
  MultimediaContentType contentType = MultimediaContentType.anime,
  String? episodeBadge,
  DateTime? publishedAt,
  int? year = 2012,
  bool isDubbed = false,
  String? relationLabel,
}) {
  return MultimediaItem(
    title: 'عنوان',
    url: 'https://example.test/anime',
    posterUrl: '',
    contentType: contentType,
    catalogType: type,
    episodeBadge: episodeBadge,
    publishedAt: publishedAt,
    year: year,
    isDubbed: isDubbed,
    relationLabel: relationLabel,
  );
}

void main() {
  test('keeps the server catalog type as-is', () {
    expect(catalogTypeLabel(_item(type: 'خاصة')), 'خاصة');
    expect(catalogTypeLabel(_item(type: 'فيلم')), 'فيلم');
    expect(catalogTypeLabel(_item(type: 'اونا')), 'اونا');
  });

  test('latest-episode cards use relative time and hide the year', () {
    final item = _item(
      episodeBadge: 'الحلقة 9',
      publishedAt: DateTime.now().subtract(const Duration(hours: 12)),
      year: 2012,
    );
    expect(multimediaCardSubtitle(item), 'منذ 12 ساعة');
    expect(multimediaCardYear(item), isNull);
  });

  test('regular cards show the catalog type and year', () {
    final item = _item(type: 'مسلسل', year: 2008);
    expect(multimediaCardSubtitle(item), 'مسلسل');
    expect(multimediaCardYear(item), 2008);
  });

  test('shows a dubbed corner badge on regular posters', () {
    expect(dubbedPosterBadge(_item(isDubbed: true)), 'مدبلج');
    expect(
      dubbedPosterBadge(_item(isDubbed: true, episodeBadge: 'الحلقة 1')),
      isNull,
    );
  });

  test('prefers the relation badge when requested', () {
    final item = _item(relationLabel: 'السابق', isDubbed: true);
    expect(
      multimediaCardPosterBadge(item, showRelationBadge: true),
      'السابق',
    );
  });
}
