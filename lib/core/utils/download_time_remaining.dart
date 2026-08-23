import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/widgets.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

import '../services/download_service.dart';

/// Formats [DownloadProgressData.timeRemaining] the same way as the episode
/// download progress dialog (Arabic dual/plural units included).
String formatDownloadTimeRemaining(
  BuildContext context,
  DownloadProgressData data,
  AppLocalizations l10n,
) {
  if (data.status == TaskStatus.paused) return '---';
  if (data.progress >= 1.0) return l10n.statusFinished;
  if (data.timeRemaining.inSeconds <= 0) return l10n.calculating;

  final duration = data.timeRemaining;
  if (Localizations.localeOf(context).languageCode == 'ar') {
    if (duration.inHours > 0) {
      final parts = <String>[
        _formatArabicUnit(
          duration.inHours,
          singular: 'ساعة',
          dual: 'ساعتان',
          plural: 'ساعات',
        ),
      ];
      final minutes = duration.inMinutes % 60;
      if (minutes > 0) {
        parts.add(
          _formatArabicUnit(
            minutes,
            singular: 'دقيقة',
            dual: 'دقيقتان',
            plural: 'دقائق',
          ),
        );
      }
      return parts.join(' و');
    }

    if (duration.inMinutes > 0) {
      final parts = <String>[
        _formatArabicUnit(
          duration.inMinutes,
          singular: 'دقيقة',
          dual: 'دقيقتان',
          plural: 'دقائق',
        ),
      ];
      final seconds = duration.inSeconds % 60;
      if (seconds > 0) {
        parts.add(
          _formatArabicUnit(
            seconds,
            singular: 'ثانية',
            dual: 'ثانيتان',
            plural: 'ثوانٍ',
          ),
        );
      }
      return parts.join(' و');
    }

    return _formatArabicUnit(
      duration.inSeconds,
      singular: 'ثانية',
      dual: 'ثانيتان',
      plural: 'ثوانٍ',
    );
  }

  if (duration.inHours > 0) {
    return '${duration.inHours}h ${duration.inMinutes % 60}m';
  }
  if (duration.inMinutes > 0) {
    return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
  }
  return '${duration.inSeconds}s';
}

String _formatArabicUnit(
  int value, {
  required String singular,
  required String dual,
  required String plural,
}) {
  if (value == 1) return singular;
  if (value == 2) return dual;
  if (value >= 3 && value <= 10) return '$value $plural';
  return '$value $singular';
}
