import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/entity/multimedia_item.dart';
import '../../../core/network/link_probe_service.dart';
import '../../../core/utils/source_text.dart';

Future<StreamResult?> showStreamSourcePicker(
  BuildContext context,
  List<StreamResult> sources, {
  required bool forDownload,
}) {
  return showModalBottomSheet<StreamResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _SourcePickerSheet(
      sources: sources,
      forDownload: forDownload,
    ),
  );
}

class _SourcePickerSheet extends ConsumerStatefulWidget {
  final List<StreamResult> sources;
  final bool forDownload;

  const _SourcePickerSheet({
    required this.sources,
    required this.forDownload,
  });

  @override
  ConsumerState<_SourcePickerSheet> createState() => _SourcePickerSheetState();
}

class _SourcePickerSheetState extends ConsumerState<_SourcePickerSheet> {
  final Map<String, LinkProbeResult> _probes = {};
  final Set<String> _probing = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _probeVisible());
  }

  Future<void> _probeVisible() async {
    final service = ref.read(linkProbeServiceProvider);
    for (final source in widget.sources) {
      final url = source.url.trim();
      if (url.isEmpty || _probes.containsKey(url) || _probing.contains(url)) {
        continue;
      }
      setState(() => _probing.add(url));
      try {
        final result = await service.probe(url, headers: source.headers);
        if (!mounted) return;
        setState(() {
          _probes[url] = result;
          _probing.remove(url);
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _probing.remove(url));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
    final rows = _buildSourcePickerRows(widget.sources);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Text(
                isArabic ? 'اختر المصدر' : 'Choose source',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  if (row.heading != null) {
                    return _SourceQualityHeader(label: row.heading!);
                  }

                  final source = row.source!;
                  final url = source.url.trim();
                  final probe = _probes[url];
                  final probing = _probing.contains(url);
                  final title = cleanSourceText(source.source);
                  final detail = buildSourceDetail([
                    probe?.resolutionLabel,
                    probe?.sizeLabel,
                    source.quality,
                  ]);

                  return ListTile(
                    contentPadding: const EdgeInsetsDirectional.only(
                      start: 36,
                      end: 20,
                    ),
                    leading: Icon(
                      widget.forDownload
                          ? Icons.file_download_outlined
                          : Icons.play_circle_outline,
                    ),
                    title: Text(
                      title.isEmpty ? source.source : title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: detail.isEmpty && !probing && probe == null
                        ? null
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (detail.isNotEmpty) Text(detail),
                              const SizedBox(height: 2),
                              _ProbeStatus(
                                probe: probe,
                                probing: probing,
                                isArabic: isArabic,
                              ),
                            ],
                          ),
                    onTap: () => Navigator.of(context).pop(source),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProbeStatus extends StatelessWidget {
  final LinkProbeResult? probe;
  final bool probing;
  final bool isArabic;

  const _ProbeStatus({
    required this.probe,
    required this.probing,
    required this.isArabic,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (probing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isArabic ? 'جاري الفحص…' : 'Checking…',
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    final result = probe;
    if (result == null) return const SizedBox.shrink();

    if (result.reachable) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_rounded, size: 14, color: Colors.green),
          const SizedBox(width: 4),
          Text(
            isArabic ? 'يعمل' : 'Working',
            style: theme.textTheme.labelSmall?.copyWith(color: Colors.green),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline_rounded, size: 14, color: cs.error),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            result.failureReason ??
                (isArabic ? 'رابط معطل' : 'Dead link'),
            style: theme.textTheme.labelSmall?.copyWith(color: cs.error),
          ),
        ),
      ],
    );
  }
}

List<_SourcePickerRow> _buildSourcePickerRows(List<StreamResult> sources) {
  final entries = <_SourcePickerEntry>[
    for (var i = 0; i < sources.length; i++)
      _SourcePickerEntry(
        source: sources[i],
        originalIndex: i,
        qualityScore: _qualityScore(sources[i].quality),
        qualityLabel: _qualityLabel(sources[i].quality),
      ),
  ];

  entries.sort((a, b) {
    final qualityCompare = b.qualityScore.compareTo(a.qualityScore);
    if (qualityCompare != 0) return qualityCompare;

    final serverCompare = _serverPriority(a.source.source)
        .compareTo(_serverPriority(b.source.source));
    if (serverCompare != 0) return serverCompare;

    final nameCompare = a.source.source
        .toLowerCase()
        .compareTo(b.source.source.toLowerCase());
    if (nameCompare != 0) return nameCompare;

    return a.originalIndex.compareTo(b.originalIndex);
  });

  final rows = <_SourcePickerRow>[];
  String? currentQuality;
  for (final entry in entries) {
    if (entry.qualityLabel != currentQuality) {
      currentQuality = entry.qualityLabel;
      rows.add(_SourcePickerRow.heading(currentQuality));
    }
    rows.add(_SourcePickerRow.source(entry.source));
  }
  return rows;
}

int _serverPriority(String source) {
  final normalized = source.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (normalized.startsWith('PD') || normalized.contains('PIXELDRAIN')) {
    return 0;
  }
  if (normalized.startsWith('MF') || normalized.contains('MEDIAFIRE')) {
    return 1;
  }
  if (normalized.startsWith('ST') || normalized.contains('STREAMTAPE')) {
    return 2;
  }
  return 10;
}

int _qualityScore(String? quality) {
  final raw = quality?.trim();
  if (raw == null || raw.isEmpty) return -1;

  final lower = raw.toLowerCase();
  final numericMatch = RegExp(r'(\d{3,4})').firstMatch(lower);
  if (numericMatch != null) {
    return int.tryParse(numericMatch.group(1)!) ?? -1;
  }

  if (lower.contains('4k') || lower.contains('uhd')) return 2160;
  if (lower.contains('fhd') || lower.contains('fullhd')) return 1080;
  if (lower == 'hd' || lower.contains('hd')) return 720;
  if (lower.contains('sd')) return 480;
  return -1;
}

String _qualityLabel(String? quality) {
  final score = _qualityScore(quality);
  if (score > 0) return '${score}p';

  final raw = quality?.trim();
  if (raw != null && raw.isNotEmpty) return raw;
  return 'Unknown';
}

class _SourcePickerEntry {
  final StreamResult source;
  final int originalIndex;
  final int qualityScore;
  final String qualityLabel;

  const _SourcePickerEntry({
    required this.source,
    required this.originalIndex,
    required this.qualityScore,
    required this.qualityLabel,
  });
}

class _SourcePickerRow {
  final String? heading;
  final StreamResult? source;

  const _SourcePickerRow.heading(this.heading) : source = null;
  const _SourcePickerRow.source(this.source) : heading = null;
}

class _SourceQualityHeader extends StatelessWidget {
  final String label;

  const _SourceQualityHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 6),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}
