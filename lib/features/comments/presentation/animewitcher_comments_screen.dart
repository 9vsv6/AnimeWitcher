import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:skystream/shared/widgets/apple_liquid_glass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:skystream/core/account/account_providers.dart';
import 'package:skystream/core/account/animewitcher_account_models.dart';
import 'package:skystream/core/account/animewitcher_comment_models.dart';
import 'package:skystream/core/account/firestore_rest_client.dart';

import 'animewitcher_replies_screen.dart';

class AnimeWitcherCommentsScreen extends ConsumerStatefulWidget {
  const AnimeWitcherCommentsScreen({
    super.key,
    required this.target,
  });

  final AnimeWitcherCommentTarget target;

  @override
  ConsumerState<AnimeWitcherCommentsScreen> createState() =>
      _AnimeWitcherCommentsScreenState();
}

class _AnimeWitcherCommentsScreenState
    extends ConsumerState<AnimeWitcherCommentsScreen> {
  static const int _pageSize = 20;

  final TextEditingController _commentController = TextEditingController();
  final Set<String> _revealedSpoilers = <String>{};
  final Set<String> _pendingLikes = <String>{};
  late final ScrollController _scrollController;

  List<AnimeWitcherComment> _comments = <AnimeWitcherComment>[];
  AnimeWitcherCommentSort _sort = AnimeWitcherCommentSort.newest;
  Object? _loadError;
  FirestoreDocument? _cursor;
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _spoiler = false;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadInitial();
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _commentController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _loadingInitial ||
        _loadingMore ||
        !_hasMore) {
      return;
    }
    if (_scrollController.position.extentAfter < 520) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    if (!mounted) return;
    setState(() {
      _loadingInitial = true;
      _loadingMore = false;
      _hasMore = true;
      _cursor = null;
      _loadError = null;
    });
    try {
      final page = await ref
          .read(animeWitcherAccountServiceProvider)
          .loadComments(
            widget.target,
            sort: _sort,
            cursor: null,
            limit: _pageSize,
          );
      if (!mounted) return;
      setState(() {
        _comments = page.items;
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loadingInitial = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loadingInitial = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingInitial || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(animeWitcherAccountServiceProvider)
          .loadComments(
            widget.target,
            sort: _sort,
            cursor: _cursor,
            limit: _pageSize,
          );
      if (!mounted) return;
      final existing = _comments.map((item) => item.path).toSet();
      final additions = page.items
          .where((item) => existing.add(item.path))
          .toList(growable: false);
      setState(() {
        _comments = <AnimeWitcherComment>[..._comments, ...additions];
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loadError = error;
      });
      _showMessage(_commentErrorText(error, _isArabic(context)));
    }
  }

  Future<void> _publish() async {
    if (_publishing) return;
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    final isArabic = _isArabic(context);
    setState(() => _publishing = true);
    try {
      await ref.read(animeWitcherAccountServiceProvider).publishComment(
            widget.target,
            text,
            spoiler: _spoiler,
          );
      if (!mounted) return;
      _commentController.clear();
      setState(() => _spoiler = false);
      _showMessage(
        isArabic
            ? 'تم نشر تعليقك وهو قيد المراجعة.'
            : 'Your comment was submitted and is under review.',
      );
      await _loadInitial();
    } catch (error) {
      if (!mounted) return;
      _showMessage(_commentErrorText(error, isArabic));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _toggleLike(AnimeWitcherComment comment) async {
    if (_pendingLikes.contains(comment.path)) return;
    final service = ref.read(animeWitcherAccountServiceProvider);
    final isArabic = _isArabic(context);
    if (!service.isSignedIn) {
      _showMessage(isArabic ? 'يجب تسجيل الدخول' : 'Sign in to like comments.');
      return;
    }
    if (comment.userId == service.accountUid ||
        comment.userId == service.snapshot.profile?.documentId) {
      return;
    }

    setState(() => _pendingLikes.add(comment.path));
    try {
      final updated = await service.toggleCommentLike(comment);
      if (!mounted) return;
      final index = _comments.indexWhere((item) => item.path == comment.path);
      if (index >= 0) {
        setState(() => _comments[index] = updated);
      }
    } catch (error) {
      if (mounted) _showMessage(_commentErrorText(error, isArabic));
    } finally {
      if (mounted) setState(() => _pendingLikes.remove(comment.path));
    }
  }

  Future<void> _openReplies(AnimeWitcherComment comment) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AnimeWitcherRepliesScreen(
          parentComment: comment,
        ),
      ),
    );
    if (!mounted) return;
    // The AnimeWitcher backend owns the authoritative replies counter.
    // Refresh the visible page after returning so it picks up server changes.
    await _loadInitial();
  }

  Future<void> _applyCommentSort(AnimeWitcherCommentSort selected) async {
    if (selected == _sort || !mounted) return;
    setState(() => _sort = selected);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    await _loadInitial();
  }

  AnimeWitcherCommentSort _commentSortFromValue(String value) {
    for (final option in AnimeWitcherCommentSort.values) {
      if (option.name == value) return option;
    }
    return _sort;
  }

  List<AppleNativeMenuItem> _commentSortMenuItems(bool isArabic) {
    return <AppleNativeMenuItem>[
      AppleNativeMenuItem(
        value: AnimeWitcherCommentSort.newest.name,
        label: _sortLabel(AnimeWitcherCommentSort.newest, isArabic),
        systemImage: 'clock',
      ),
      AppleNativeMenuItem(
        value: AnimeWitcherCommentSort.oldest.name,
        label: _sortLabel(AnimeWitcherCommentSort.oldest, isArabic),
        systemImage: 'clock.arrow.circlepath',
      ),
      AppleNativeMenuItem(
        value: AnimeWitcherCommentSort.mostLiked.name,
        label: _sortLabel(AnimeWitcherCommentSort.mostLiked, isArabic),
        systemImage: 'heart',
      ),
    ];
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isArabic(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';

  @override
  Widget build(BuildContext context) {
    final isArabic = _isArabic(context);
    final accountState = ref.watch(animeWitcherAccountControllerProvider);
    final service = ref.read(animeWitcherAccountServiceProvider);
    final isSignedIn = accountState.asData?.value.isSignedIn ?? service.isSignedIn;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AppBar(
            centerTitle: false,
            titleSpacing: 16,
            leading: AppleLiquidGlassBackButton(
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Align(
              alignment: isArabic ? Alignment.centerRight : Alignment.centerLeft,
              child: Directionality(
                textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                child: Text(isArabic ? 'التعليقات' : 'Comments'),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AppleNativeMenuButton(
                  accessibilityLabel:
                      isArabic ? 'ترتيب التعليقات' : 'Sort comments',
                  systemImage: 'arrow.up.arrow.down',
                  fallbackIcon: Icons.filter_list_rounded,
                  size: 46,
                  selectedValue: _sort.name,
                  items: _commentSortMenuItems(isArabic),
                  onSelected: (value) {
                    _applyCommentSort(_commentSortFromValue(value));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (widget.target.title.trim().isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Directionality(
                textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                child: Text(
                  widget.target.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
          Expanded(child: _buildCommentsBody(context, isArabic)),
          _buildComposer(context, isArabic, isSignedIn),
        ],
      ),
    );
  }

  Widget _buildCommentsBody(BuildContext context, bool isArabic) {
    if (_loadingInitial) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _comments.isEmpty) {
      return _CommentsLoadError(
        isArabic: isArabic,
        onRetry: _loadInitial,
      );
    }
    if (_comments.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadInitial,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.25),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                isArabic
                    ? 'لا توجد تعليقات منشورة بعد.'
                    : 'No published comments yet.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInitial,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: _comments.length + (_hasMore || _loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= _comments.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            );
          }
          return _buildCommentCard(context, _comments[index], isArabic);
        },
      ),
    );
  }

  Widget _buildCommentCard(
    BuildContext context,
    AnimeWitcherComment comment,
    bool isArabic,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final photo = comment.userPhotoUrl?.trim() ?? '';
    final reveal = !comment.spoiler || _revealedSpoilers.contains(comment.path);
    final likePending = _pendingLikes.contains(comment.path);

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Directionality(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: colors.surfaceContainerHighest,
                    backgroundImage:
                        photo.isEmpty ? null : CachedNetworkImageProvider(photo),
                    child: photo.isEmpty
                        ? Icon(
                            Icons.person_rounded,
                            color: colors.onSurfaceVariant,
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          comment.userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _commentTimeAgo(comment.date, isArabic),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (reveal)
              Directionality(
                textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                child: Text(
                  comment.text,
                  textAlign: TextAlign.start,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
              )
            else
              Align(
                alignment:
                    isArabic ? Alignment.centerRight : Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() => _revealedSpoilers.add(comment.path));
                  },
                  icon: const Icon(Icons.visibility_off_rounded),
                  label: Text(
                    isArabic
                        ? 'تعليق يحتوي على حرق — إظهار'
                        : 'Spoiler comment — reveal',
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Directionality(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _ReactionButton(
                    icon: comment.likedByMe
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    count: comment.likes,
                    active: comment.likedByMe,
                    busy: likePending,
                    tooltip: isArabic ? 'إعجاب' : 'Like',
                    onTap: () => _toggleLike(comment),
                  ),
                  const SizedBox(width: 14),
                  _ReactionButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    count: comment.replies,
                    tooltip: isArabic ? 'الردود' : 'Replies',
                    onTap: () => _openReplies(comment),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer(
    BuildContext context,
    bool isArabic,
    bool isSignedIn,
  ) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: isSignedIn
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 500,
                      textDirection:
                          isArabic ? TextDirection.rtl : TextDirection.ltr,
                      decoration: InputDecoration(
                        hintText: isArabic ? 'اكتب تعليقًا...' : 'Write a comment...',
                        counterText: '',
                        filled: true,
                        fillColor: colors.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: isArabic ? 'يحتوي على حرق' : 'Contains spoiler',
                    onPressed: () => setState(() => _spoiler = !_spoiler),
                    icon: Icon(
                      _spoiler
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_outlined,
                      color: _spoiler ? colors.primary : colors.onSurfaceVariant,
                    ),
                  ),
                  IconButton.filled(
                    tooltip: isArabic ? 'نشر' : 'Publish',
                    onPressed: _publishing ? null : _publish,
                    icon: _publishing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        isArabic
                            ? 'سجّل الدخول إلى حساب AnimeWitcher لإضافة تعليق.'
                            : 'Sign in to your AnimeWitcher account to comment.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.icon,
    required this.count,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.busy = false,
  });

  final IconData icon;
  final int count;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = active ? colors.primary : colors.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              else
                Icon(icon, size: 19, color: foreground),
              const SizedBox(width: 5),
              Text(
                '$count',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: foreground,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentsLoadError extends StatelessWidget {
  const _CommentsLoadError({
    required this.isArabic,
    required this.onRetry,
  });

  final bool isArabic;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40),
            const SizedBox(height: 10),
            Text(
              isArabic ? 'تعذر تحميل التعليقات.' : 'Could not load comments.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(isArabic ? 'إعادة المحاولة' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

String _sortLabel(AnimeWitcherCommentSort sort, bool isArabic) {
  return switch (sort) {
    AnimeWitcherCommentSort.newest => isArabic ? 'الأحدث' : 'Newest',
    AnimeWitcherCommentSort.oldest => isArabic ? 'الأقدم' : 'Oldest',
    AnimeWitcherCommentSort.mostLiked =>
      isArabic ? 'الأكثر اعجابا' : 'Most liked',
  };
}

String _commentErrorText(Object error, bool isArabic) {
  if (error is AnimeWitcherAccountException) {
    return switch (error.code) {
      'not-signed-in' => isArabic
          ? 'يجب تسجيل الدخول قبل تنفيذ هذه العملية.'
          : 'Sign in before doing that.',
      'comment-empty' =>
        isArabic ? 'يرجى إدخال نص.' : 'Enter some text first.',
      'comment-too-long' => isArabic
          ? 'الحد الأعلى للنص 500 حرف.'
          : 'The maximum length is 500 characters.',
      'comment-banned' => isArabic
          ? 'تم حظرك من التعليق.'
          : 'This account is blocked from commenting.',
      'comment-account-too-new' => isArabic
          ? 'يجب أن يمر على إنشاء حسابك 7 أيام قبل أن تتمكن من كتابة التعليقات.'
          : 'Your account must be at least 7 days old before commenting.',
      'comment-cooldown' => isArabic
          ? 'انتظر قليلاً حتى يمكنك التعليق مرة أخرى.'
          : 'Wait a moment before commenting again.',
      'comment-limit' => isArabic
          ? 'لقد وصلت للحد الأقصى لعدد التعليقات على هذا المحتوى.'
          : 'You reached the comment limit for this item.',
      'comments-closed' => isArabic
          ? 'تم إيقاف التعليقات على هذا المحتوى.'
          : 'Comments are disabled for this item.',
      'replies-closed' => isArabic
          ? 'تم إيقاف الردود على هذا التعليق.'
          : 'Replies are disabled for this comment.',
      _ => error.message,
    };
  }
  return isArabic ? 'حدث خطأ. حاول مرة أخرى.' : 'Something went wrong. Try again.';
}

String _commentTimeAgo(DateTime? date, bool isArabic) {
  if (date == null) return '';
  final raw = DateTime.now().difference(date);
  final elapsed = raw.isNegative ? Duration.zero : raw;
  if (elapsed.inMinutes < 1) return isArabic ? 'منذ لحظات' : 'just now';
  if (elapsed.inMinutes < 60) {
    final value = elapsed.inMinutes;
    return isArabic
        ? value == 1
            ? 'منذ دقيقة'
            : 'منذ $value دقيقة'
        : value == 1
            ? '1 minute ago'
            : '$value minutes ago';
  }
  if (elapsed.inHours < 24) {
    final value = elapsed.inHours;
    return isArabic
        ? value == 1
            ? 'منذ ساعة'
            : 'منذ $value ساعة'
        : value == 1
            ? '1 hour ago'
            : '$value hours ago';
  }
  if (elapsed.inDays < 30) {
    final value = elapsed.inDays;
    return isArabic
        ? value == 1
            ? 'منذ يوم'
            : 'منذ $value يوم'
        : value == 1
            ? '1 day ago'
            : '$value days ago';
  }
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year}';
}
