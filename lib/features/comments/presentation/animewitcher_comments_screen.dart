import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:skystream/core/account/account_providers.dart';
import 'package:skystream/core/account/animewitcher_account_models.dart';
import 'package:skystream/core/account/animewitcher_comment_models.dart';

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
  final TextEditingController _commentController = TextEditingController();
  final Set<String> _revealedSpoilers = <String>{};
  late Future<List<AnimeWitcherComment>> _commentsFuture;
  bool _spoiler = false;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    _commentsFuture = _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<List<AnimeWitcherComment>> _loadComments() {
    return ref
        .read(animeWitcherAccountServiceProvider)
        .loadComments(widget.target);
  }

  void _reload() {
    setState(() => _commentsFuture = _loadComments());
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic
                ? 'تم نشر تعليقك وهو قيد المراجعة.'
                : 'Your comment was submitted and is under review.',
          ),
        ),
      );
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_commentErrorText(error, isArabic))),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
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
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Align(
              alignment: isArabic
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Directionality(
                textDirection:
                    isArabic ? TextDirection.rtl : TextDirection.ltr,
                child: Text(isArabic ? 'التعليقات' : 'Comments'),
              ),
            ),
            actions: [
              IconButton(
                tooltip: isArabic ? 'تحديث' : 'Refresh',
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded),
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
              child: Text(
                widget.target.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: isArabic ? TextAlign.right : TextAlign.left,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          Expanded(
            child: FutureBuilder<List<AnimeWitcherComment>>(
              future: _commentsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _CommentsLoadError(
                    isArabic: isArabic,
                    onRetry: _reload,
                  );
                }
                final comments = snapshot.data ?? const <AnimeWitcherComment>[];
                if (comments.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        isArabic
                            ? 'لا توجد تعليقات منشورة بعد.'
                            : 'No published comments yet.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    final future = _loadComments();
                    setState(() => _commentsFuture = future);
                    await future;
                  },
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: comments.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _buildCommentCard(
                      context,
                      comments[index],
                      isArabic,
                    ),
                  ),
                );
              },
            ),
          ),
          _buildComposer(context, isArabic, isSignedIn),
        ],
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
    final reveal = !comment.spoiler || _revealedSpoilers.contains(comment.id);
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
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
                    setState(() => _revealedSpoilers.add(comment.id));
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
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(
                  Icons.favorite_border_rounded,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text('${comment.likes}'),
                const SizedBox(width: 16),
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text('${comment.replies}'),
              ],
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
                        hintText: isArabic
                            ? 'اكتب تعليقًا...'
                            : 'Write a comment...',
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
              isArabic
                  ? 'تعذر تحميل التعليقات.'
                  : 'Could not load comments.',
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

String _commentErrorText(Object error, bool isArabic) {
  if (error is AnimeWitcherAccountException) {
    return switch (error.code) {
      'not-signed-in' => isArabic
          ? 'يجب تسجيل الدخول قبل إضافة تعليق.'
          : 'Sign in before adding a comment.',
      'comment-empty' =>
        isArabic ? 'يرجى إدخال نص.' : 'Enter a comment first.',
      'comment-too-long' => isArabic
          ? 'الحد الأعلى للتعليق 500 حرف.'
          : 'Comments can contain at most 500 characters.',
      'comment-banned' => isArabic
          ? 'تم حظرك من التعليق.'
          : 'This account is blocked from commenting.',
      'comment-account-too-new' => isArabic
          ? 'يجب أن يمر على إنشاء حسابك 7 أيام قبل أن تتمكن من كتابة التعليقات.'
          : 'Your account must be at least 7 days old before commenting.',
      'comment-cooldown' => isArabic
          ? 'انتظر قليلًا حتى يمكنك التعليق مرة أخرى.'
          : 'Wait a moment before commenting again.',
      'comment-limit' => isArabic
          ? 'لقد وصلت للحد الأقصى لعدد التعليقات على هذا المحتوى.'
          : 'You reached the comment limit for this item.',
      'comments-closed' => isArabic
          ? 'تم إيقاف التعليقات على هذا المحتوى.'
          : 'Comments are disabled for this item.',
      _ => error.message,
    };
  }
  return isArabic ? 'تعذر نشر التعليق.' : 'Could not publish the comment.';
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
