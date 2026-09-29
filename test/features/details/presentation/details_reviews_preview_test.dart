import 'package:animewitcher/core/account/account_providers.dart';
import 'package:animewitcher/core/account/animewitcher_account_service.dart';
import 'package:animewitcher/core/account/animewitcher_comment_models.dart';
import 'package:animewitcher/core/account/firestore_rest_client.dart';
import 'package:animewitcher/core/domain/entity/multimedia_item.dart';
import 'package:animewitcher/core/storage/secure_token_storage.dart';
import 'package:animewitcher/core/storage/storage_service.dart';
import 'package:animewitcher/features/details/presentation/widgets/details_comments_preview.dart';
import 'package:animewitcher/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _PreviewService extends AnimeWitcherAccountService {
  _PreviewService()
      : super(
          storage: StorageService(),
          secureStorage: SecureTokenStorage(StorageService()),
        );

  @override
  Future<AnimeWitcherCommentPage> loadComments(
    AnimeWitcherCommentTarget target, {
    AnimeWitcherCommentSort sort = AnimeWitcherCommentSort.newest,
    FirestoreDocument? cursor,
    int limit = 20,
  }) async {
    return const AnimeWitcherCommentPage(
      items: <AnimeWitcherComment>[],
      cursor: null,
      hasMore: false,
    );
  }
}

void main() {
  testWidgets('details footer shows reviews where comments used to be', (
    tester,
  ) async {
    final item = MultimediaItem(
      title: 'Anime',
      url: 'https://animewitcher.com/anime/anime-id',
      posterUrl: '',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          animeWitcherAccountServiceProvider.overrideWithValue(
            _PreviewService(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DetailsCommentsPreview(item: item),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('المراجعات'), findsOneWidget);
    expect(find.text('التعليقات'), findsNothing);
    expect(find.text('لا توجد مراجعات منشورة بعد.'), findsOneWidget);
  });
}
