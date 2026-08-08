import 'package:url_launcher/url_launcher.dart';

import '../../../core/domain/entity/multimedia_item.dart';

Future<void> openNewsUrl(NewsItem item) async {
  final rawUrl = item.newsUrl?.trim();
  if (rawUrl == null || rawUrl.isEmpty) return;

  final uri = Uri.tryParse(rawUrl);
  if (uri == null || !uri.hasScheme) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
