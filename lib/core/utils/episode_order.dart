import '../domain/entity/multimedia_item.dart';

/// Episodes in the order the user is meant to see them.
///
/// The order the server returned is the canonical one: the Episodes tab keeps
/// it as-is and the sort toggle only flips it. The player's episode picker uses
/// this same function so the two lists never disagree.
List<Episode> episodesInDisplayOrder(
  Iterable<Episode> episodes, {
  required bool ascending,
}) {
  final ordered = List<Episode>.of(episodes);
  return ascending ? ordered : ordered.reversed.toList(growable: false);
}
