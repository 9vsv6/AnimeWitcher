import '../../../core/account/animewitcher_comment_models.dart';
import '../../../core/domain/entity/multimedia_item.dart';

/// Parsed APK details ratings fields for the details page row.
///
/// Witcher score is `rating.rate`. MAL uses `details.mal_mean` and
/// `details.mal_num_scoring_users`. Vote counts are never invented.
class AnimeDetailsRatings {
  const AnimeDetailsRatings({
    required this.animeId,
    this.witcherScore,
    this.witcherVoteCount,
    this.malMean,
    this.malScoringUsers,
    this.malId,
    this.imdbId,
    this.isUnaired = false,
    this.reviewsClosed = false,
  });

  final String animeId;
  final double? witcherScore;
  final int? witcherVoteCount;
  final double? malMean;
  final int? malScoringUsers;
  final String? malId;
  final String? imdbId;
  final bool isUnaired;
  final bool reviewsClosed;

  /// APK hides the MAL card when neither `mal_id` nor `imdb_id` is present.
  /// The score UI also needs `mal_mean`, so the column stays hidden without it.
  bool get showMalColumn {
    if (malMean == null) return false;
    return _hasId(malId) || _hasId(imdbId);
  }

  /// Displayed MAL scoring-user count. Unaired titles are forced to 0.
  int? get displayedMalScoringUsers {
    if (!showMalColumn) return null;
    if (isUnaired) return 0;
    return malScoringUsers;
  }

  bool get canRate => !isUnaired && animeId.isNotEmpty;

  factory AnimeDetailsRatings.fromItem(MultimediaItem item) {
    final data = item.syncData ?? const <String, String>{};
    final malId = _firstNonEmpty(<String?>[
      data['malId'],
      data['mal_id'],
      data['awMalId'],
    ]);
    final imdbId = _firstNonEmpty(<String?>[
      data['awImdbId'],
      data['imdbId'],
      data['imdb_id'],
      item.imdbId,
    ]);
    return AnimeDetailsRatings(
      animeId: animeWitcherAnimeIdFromItem(item),
      witcherScore: _positiveScore(data['awScore']),
      witcherVoteCount: _positiveInt(data['awScoreCount']),
      malMean: _positiveScore(data['awMalScore']),
      malScoringUsers: _nonNegativeInt(data['awMalScoringUsers']),
      malId: malId,
      imdbId: imdbId,
      isUnaired: _isUnaired(item, data),
      reviewsClosed: _isTruthy(data['awReviewsClosed']),
    );
  }
}

String formatRatingScore(double score) {
  return score
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'[.]$'), '');
}

bool _hasId(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty || text == '0') return false;
  return true;
}

bool _isUnaired(MultimediaItem item, Map<String, String> data) {
  if (item.status == ShowStatus.upcoming) return true;
  final state = (data['awState'] ?? '').trim();
  return state == 'لم يتم بثه بعد';
}

bool _isTruthy(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  return value == 'true' || value == '1' || value == 'yes';
}

double? _positiveScore(String? raw) {
  final normalized = _normalizeDigits((raw ?? '').trim());
  if (normalized.isEmpty) return null;
  final match = RegExp(r'[0-9]+(?:[.][0-9]+)?').firstMatch(normalized);
  final score = match == null ? null : double.tryParse(match.group(0)!);
  if (score == null || score <= 0) return null;
  return score;
}

int? _positiveInt(String? raw) {
  final value = _nonNegativeInt(raw);
  if (value == null || value <= 0) return null;
  return value;
}

int? _nonNegativeInt(String? raw) {
  final normalized = _normalizeDigits((raw ?? '').trim());
  if (normalized.isEmpty) return null;
  final match = RegExp(r'[0-9]+').firstMatch(normalized);
  if (match == null) return null;
  return int.tryParse(match.group(0)!);
}

String _normalizeDigits(String value) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const eastern = '۰۱۲۳۴۵۶۷۸۹';
  return value
      .replaceAllMapped(
        RegExp(r'[٠-٩]'),
        (match) => '${arabic.indexOf(match.group(0)!)}',
      )
      .replaceAllMapped(
        RegExp(r'[۰-۹]'),
        (match) => '${eastern.indexOf(match.group(0)!)}',
      );
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final raw in values) {
    final value = raw?.trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return null;
}
