import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';

/// Shows one continuous progress bar for the whole download.
///
/// Parallel connections remain an implementation detail of the download
/// engine. The bar intentionally uses only the parent task's aggregate
/// progress instead of splitting the track or calculating per-part progress.
class SegmentedDownloadProgress extends StatelessWidget {
  const SegmentedDownloadProgress({
    super.key,
    required this.task,
    required this.value,
    required this.backgroundColor,
    required this.borderRadius,
    this.chunkProgress,
    this.height = 4,
  }) : assert(height > 0);

  /// Retained for source compatibility with existing download tiles. Parallel
  /// task details do not affect how the progress bar is rendered.
  final Task task;

  /// Aggregate progress for the entire download, from 0 to 1.
  final double value;
  final Color backgroundColor;
  final BorderRadius borderRadius;

  /// Retained for source compatibility. Per-chunk progress is deliberately
  /// ignored so the UI never performs segment calculations.
  final Map<String, double>? chunkProgress;
  final double height;

  @override
  Widget build(BuildContext context) {
    final progress = value.clamp(0.0, 1.0).toDouble();

    return Semantics(
      label: 'Download progress',
      value: '${(progress * 100).floor()}%',
      child: ClipRRect(
        borderRadius: borderRadius,
        child: SizedBox(
          height: height,
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: backgroundColor,
          ),
        ),
      ),
    );
  }
}
