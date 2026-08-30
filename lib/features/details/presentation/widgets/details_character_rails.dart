import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/account/animewitcher_character_models.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../shared/widgets/paged_rail.dart';
import '../../../characters/presentation/character_card.dart';
import 'details_poster_grid.dart';

class DetailsCharacterRails extends StatelessWidget {
  const DetailsCharacterRails({
    super.key,
    required this.cast,
    required this.onCharacterTap,
    this.onShowMore,
  });

  final List<Actor> cast;
  final void Function(Actor actor) onCharacterTap;
  final void Function(String role)? onShowMore;

  static List<Actor> mainCast(List<Actor> cast) {
    return cast
        .where((actor) => actor.role == 'شخصية رئيسية')
        .toList(growable: false);
  }

  static List<Actor> supportingCast(List<Actor> cast) {
    return cast
        .where((actor) => actor.role != 'شخصية رئيسية')
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final main = mainCast(cast);
    final supporting = supportingCast(cast);
    if (main.isEmpty && supporting.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (main.isNotEmpty)
          _CharacterRoleRail(
            title: animeWitcherMainCharactersHeader,
            characters: main,
            role: 'Main',
            onCharacterTap: onCharacterTap,
            onShowMore: onShowMore,
          ),
        if (main.isNotEmpty && supporting.isNotEmpty)
          const SizedBox(height: 18),
        if (supporting.isNotEmpty)
          _CharacterRoleRail(
            title: animeWitcherSupportingCharactersHeader,
            characters: supporting,
            role: 'Supporting',
            onCharacterTap: onCharacterTap,
            onShowMore: onShowMore,
          ),
      ],
    );
  }
}

class _CharacterRoleRail extends StatefulWidget {
  const _CharacterRoleRail({
    required this.title,
    required this.characters,
    required this.role,
    required this.onCharacterTap,
    this.onShowMore,
  });

  final String title;
  final List<Actor> characters;
  final String role;
  final void Function(Actor actor) onCharacterTap;
  final void Function(String role)? onShowMore;

  @override
  State<_CharacterRoleRail> createState() => _CharacterRoleRailState();
}

class _CharacterRoleRailState extends State<_CharacterRoleRail> {
  static const _nestedTabLock = Duration(milliseconds: 350);

  late final ScrollController _controller;
  var _acceptScroll = false;
  Timer? _unlockTimer;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController(
      initialScrollOffset: 0,
      keepScrollOffset: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _lockThenPinToStart());
  }

  @override
  void didUpdateWidget(covariant _CharacterRoleRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.characters.length != widget.characters.length ||
        oldWidget.role != widget.role) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pinToRtlStart());
    }
  }

  @override
  void dispose() {
    _unlockTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Offset 0 is the RTL start (right). Nested extra-tab animation can fling
  /// the rail to maxScrollExtent; keep physics locked until that settles.
  void _lockThenPinToStart() {
    _pinToRtlStart();
    _unlockTimer?.cancel();
    _unlockTimer = Timer(_nestedTabLock, () {
      if (!mounted) return;
      _pinToRtlStart();
      setState(() => _acceptScroll = true);
    });
  }

  void _pinToRtlStart() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    if (position.pixels != position.minScrollExtent) {
      _controller.jumpTo(position.minScrollExtent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showMore =
        animeWitcherCastStripShowsMore(widget.characters.length) &&
        widget.onShowMore != null;
    final visibleCount = animeWitcherCastStripVisibleCount(
      widget.characters.length,
    );
    const cardWidth = 110.0;
    const rowHeight = 198.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            widget.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(
          height: rowHeight,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: PagedRail(
              key: ValueKey('details-character-rail-${widget.role}'),
              controller: _controller,
              physics: _acceptScroll
                  ? const BouncingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              itemExtent: cardWidth + 12,
              padding: EdgeInsets.zero,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemCount: visibleCount + (showMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (showMore && index >= visibleCount) {
                  return SizedBox(
                    key: ValueKey(
                      'details-character-${widget.role}-more',
                    ),
                    width: cardWidth,
                    height: rowHeight,
                    child: DetailsShowMoreTile(
                      compact: true,
                      onTap: () => widget.onShowMore!(widget.role),
                    ),
                  );
                }
                return SizedBox(
                  width: cardWidth,
                  height: rowHeight,
                  child: CharacterPosterCard(
                    key: ValueKey(
                      'details-character-${widget.role}-$index',
                    ),
                    character: AnimeWitcherCharacterHit(
                      id: widget.characters[index].id?.trim() ?? '',
                      name: widget.characters[index].name,
                      imageUrl: widget.characters[index].image,
                      likes: widget.characters[index].likes,
                    ),
                    onTap: (widget.characters[index].id?.trim() ?? '').isEmpty
                        ? () {}
                        : () => widget.onCharacterTap(widget.characters[index]),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
