import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

import '../../../core/extensions/extension_manager.dart';
import '../../../core/extensions/models/extension_plugin.dart';
import '../../../core/storage/extension_repository.dart';
import '../../../core/storage/settings_repository.dart';
import '../../../shared/widgets/loading_indicator.dart';

class PluginSettingsScreen extends ConsumerStatefulWidget {
  final ExtensionPlugin plugin;

  const PluginSettingsScreen({super.key, required this.plugin});

  @override
  ConsumerState<PluginSettingsScreen> createState() =>
      _PluginSettingsScreenState();
}

class _PluginSettingsScreenState extends ConsumerState<PluginSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<PluginSettingDefinition> _definitions = const [];
  List<PluginSubProvider> _providers = const [];
  final Map<String, String> _values = {};
  final Map<String, bool> _providerEnabled = {};
  final Map<String, TextEditingController> _controllers = {};
  String _selectedDomain = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final manager = ref.read(extensionManagerProvider.notifier);
      final definitions = await manager.getSettingsForPlugin(widget.plugin);
      final providers = manager.getProvidersForPlugin(widget.plugin);
      final storage = ref.read(extensionRepositoryProvider);
      final settingsRepository = ref.read(settingsRepositoryProvider);
      final savedBaseUrl = settingsRepository.getCustomBaseUrl(
        widget.plugin.packageName,
      );

      for (final controller in _controllers.values) {
        controller.dispose();
      }
      _controllers.clear();
      _values.clear();
      _providerEnabled.clear();

      for (final definition in definitions) {
        String value;
        if (definition.isBaseUrl) {
          value =
              savedBaseUrl ??
              (definition.defaultValue.isNotEmpty
                  ? definition.defaultValue
                  : (widget.plugin.manifest['baseUrl']?.toString() ?? ''));
        } else {
          value =
              storage.getExtensionData(
                '${widget.plugin.packageName}:${definition.key}',
              ) ??
              definition.defaultValue;
        }

        if (definition.type == PluginSettingType.select &&
            definition.options.isNotEmpty &&
            !definition.options.any((option) => option.value == value)) {
          value = definition.options.first.value;
        }
        if (definition.type == PluginSettingType.toggleGroup) {
          value = _normalizedToggleGroupValue(definition, value);
        }

        _values[definition.key] = value;
        if (definition.type == PluginSettingType.text ||
            definition.type == PluginSettingType.url) {
          _controllers[definition.key] = TextEditingController(text: value);
        }
      }

      for (final provider in providers) {
        final saved = storage.getExtensionData(
          '${widget.plugin.packageName}:'
          '_provider_enabled_${provider.id}',
        );
        _providerEnabled[provider.id] = saved == null ? true : saved == 'true';
      }

      final domains = widget.plugin.domains ?? const <PluginDomain>[];
      _selectedDomain =
          savedBaseUrl ??
          (domains.isNotEmpty
              ? domains.first.url
              : (widget.plugin.manifest['baseUrl']?.toString() ?? ''));

      if (!mounted) return;
      setState(() {
        _definitions = definitions;
        _providers = providers;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  bool _boolValue(String key) {
    final value = (_values[key] ?? '').trim().toLowerCase();
    return value == 'true' || value == '1' || value == 'yes' || value == 'on';
  }

  bool _boolFromDynamic(dynamic value, {required bool fallback}) {
    if (value is bool) return value;
    if (value == null) return fallback;
    final normalized = value.toString().trim().toLowerCase();
    if (const {'true', '1', 'yes', 'on'}.contains(normalized)) return true;
    if (const {'false', '0', 'no', 'off'}.contains(normalized)) return false;
    return fallback;
  }

  Map<String, bool> _toggleGroupValues(
    PluginSettingDefinition definition, [
    String? rawValue,
  ]) {
    final values = <String, bool>{
      for (final option in definition.options)
        option.value: option.defaultBool,
    };
    final raw = rawValue ?? _values[definition.key] ?? definition.defaultValue;
    if (raw.trim().isEmpty) return values;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final option in definition.options) {
          values[option.value] = _boolFromDynamic(
            decoded[option.value],
            fallback: option.defaultBool,
          );
        }
      }
    } catch (_) {
      // Invalid or legacy values fall back to the option defaults.
    }
    return values;
  }

  String _normalizedToggleGroupValue(
    PluginSettingDefinition definition,
    String rawValue,
  ) {
    return jsonEncode(_toggleGroupValues(definition, rawValue));
  }

  IconData _toggleGroupOptionIcon(PluginSettingOption option) {
    final icon = (option.icon ?? option.value).toLowerCase();
    if (icon.contains('trailer') || icon.contains('video')) {
      return Icons.movie_outlined;
    }
    if (icon.contains('character') || icon.contains('cast')) {
      return Icons.people_outline_rounded;
    }
    if (icon.contains('score') || icon.contains('rating')) {
      return Icons.star_outline_rounded;
    }
    if (icon.contains('year') || icon.contains('date')) {
      return Icons.calendar_today_outlined;
    }
    if (icon.contains('status')) return Icons.sensors_rounded;
    if (icon.contains('duration')) return Icons.timer_outlined;
    if (icon.contains('count')) return Icons.format_list_numbered_rounded;
    if (icon.contains('next') || icon.contains('airing')) {
      return Icons.schedule_rounded;
    }
    if (icon.contains('season')) return Icons.layers_outlined;
    if (icon.contains('banner') || icon.contains('image')) {
      return Icons.image_outlined;
    }
    if (icon.contains('title')) return Icons.title_rounded;
    if (icon.contains('description') || icon.contains('overview')) {
      return Icons.description_outlined;
    }
    if (icon.contains('genre')) return Icons.category_outlined;
    if (icon.contains('studio')) return Icons.business_outlined;
    if (icon.contains('format') || icon.contains('type')) {
      return Icons.movie_filter_outlined;
    }
    if (icon.contains('source')) return Icons.auto_stories_outlined;
    return Icons.tune_rounded;
  }

  String _toggleGroupSummary(PluginSettingDefinition definition) {
    final values = _toggleGroupValues(definition);
    final enabled = values.values.where((value) => value).length;
    if (Localizations.localeOf(context).languageCode == 'ar') {
      return '$enabled من ${definition.options.length} مفعّلة';
    }
    return '$enabled of ${definition.options.length} enabled';
  }

  Future<void> _showToggleGroupDialog(
    PluginSettingDefinition definition,
  ) async {
    if (_saving || definition.options.isEmpty) return;
    final values = _toggleGroupValues(definition);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              surfaceTintColor: Colors.transparent,
              title: Text(definition.title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: definition.options
                      .map(
                        (option) {
                          final description = option.description?.trim();
                          return SwitchListTile(
                            secondary: Icon(_toggleGroupOptionIcon(option)),
                            title: Text(option.label),
                            subtitle: description == null || description.isEmpty
                                ? null
                                : Text(description),
                            value: values[option.value] ?? option.defaultBool,
                            onChanged: (enabled) {
                              values[option.value] = enabled;
                              setDialogState(() {});
                              if (!mounted) return;
                              setState(() {
                                _values[definition.key] = jsonEncode(values);
                              });
                            },
                          );
                        },
                      )
                      .toList(growable: false),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    AppLocalizations.of(dialogContext)!.close,
                    style: TextStyle(
                      color: Theme.of(
                        dialogContext,
                      ).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _normalizedUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(value)) {
      value = 'https://$value';
    }
    value = value.replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const FormatException('Enter a valid HTTP or HTTPS URL');
    }
    return uri.origin;
  }

  Future<void> _save() async {
    if (_saving || _loading) return;
    setState(() => _saving = true);

    try {
      final storage = ref.read(extensionRepositoryProvider);
      final settingsRepository = ref.read(settingsRepositoryProvider);
      final manager = ref.read(extensionManagerProvider.notifier);
      var shouldReload = false;
      final hasScriptBaseUrl = _definitions.any(
        (definition) => definition.isBaseUrl,
      );

      for (final definition in _definitions) {
        var value =
            _controllers[definition.key]?.text ??
            _values[definition.key] ??
            definition.defaultValue;

        if (definition.type == PluginSettingType.url) {
          value = _normalizedUrl(value);
        }

        if (definition.isBaseUrl) {
          await settingsRepository.setCustomBaseUrl(
            widget.plugin.packageName,
            value.isEmpty ? null : value,
          );
          shouldReload = true;
        } else {
          await storage.setExtensionData(
            '${widget.plugin.packageName}:${definition.key}',
            value,
          );
          shouldReload = shouldReload || definition.reloadOnChange;
        }
        _values[definition.key] = value;
      }

      if (!hasScriptBaseUrl && (widget.plugin.domains?.isNotEmpty ?? false)) {
        await settingsRepository.setCustomBaseUrl(
          widget.plugin.packageName,
          _selectedDomain.isEmpty ? null : _selectedDomain,
        );
        shouldReload = true;
      }

      for (final provider in _providers) {
        await storage.setExtensionData(
          '${widget.plugin.packageName}:'
          '_provider_enabled_${provider.id}',
          (_providerEnabled[provider.id] ?? true) ? 'true' : 'false',
        );
        shouldReload = true;
      }

      if (shouldReload) {
        await manager.reloadPlugin(widget.plugin);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Extension settings saved')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save settings: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildSetting(
    BuildContext context,
    PluginSettingDefinition definition,
  ) {
    switch (definition.type) {
      case PluginSettingType.toggle:
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(definition.title),
            subtitle: definition.description == null
                ? null
                : Text(definition.description!),
            value: _boolValue(definition.key),
            onChanged: _saving
                ? null
                : (value) {
                    setState(() {
                      _values[definition.key] = value ? 'true' : 'false';
                    });
                  },
          ),
        );

      case PluginSettingType.toggleGroup:
        final colors = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Material(
            color: colors.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: colors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              leading: const Icon(Icons.tune_rounded),
              title: Text(definition.title),
              subtitle: Text(
                [
                  _toggleGroupSummary(definition),
                  if (definition.description != null &&
                      definition.description!.trim().isNotEmpty)
                    definition.description!,
                ].join('\n'),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _saving ? null : () => _showToggleGroupDialog(definition),
            ),
          ),
        );

      case PluginSettingType.select:
        final current = _values[definition.key];
        final selected =
            definition.options.any((option) => option.value == current)
            ? current
            : null;

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: DropdownButtonFormField<String>(
            key: ValueKey('${definition.key}:$selected'),
            initialValue: selected,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: definition.title,
              helperText: definition.description,
              border: const OutlineInputBorder(),
            ),
            items: definition.options
                .map(
                  (option) => DropdownMenuItem<String>(
                    value: option.value,
                    child: Text(option.label, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(growable: false),
            onChanged: _saving
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _values[definition.key] = value;
                    });
                  },
          ),
        );

      case PluginSettingType.text:
      case PluginSettingType.url:
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: TextField(
            controller: _controllers[definition.key],
            enabled: !_saving,
            keyboardType: definition.type == PluginSettingType.url
                ? TextInputType.url
                : TextInputType.text,
            autocorrect: definition.type != PluginSettingType.url,
            enableSuggestions: definition.type != PluginSettingType.url,
            decoration: InputDecoration(
              labelText: definition.title,
              helperText: definition.description,
              hintText: definition.type == PluginSettingType.url
                  ? 'https://example.com'
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final domains = widget.plugin.domains ?? const <PluginDomain>[];
    final hasScriptBaseUrl = _definitions.any(
      (definition) => definition.isBaseUrl,
    );
    final hasContent =
        _definitions.isNotEmpty ||
        _providers.isNotEmpty ||
        (domains.isNotEmpty && !hasScriptBaseUrl);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.pluginSettings(widget.plugin.name)),
        actions: [
          IconButton(
            tooltip: 'Save',
            onPressed: _loading || _saving ? null : _save,
            icon: _saving
                ? const AppLoadingIndicator(
                    constraints: BoxConstraints.tightFor(width: 20, height: 20),
                  )
                : const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: AppLoadingIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : !hasContent
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This extension does not define configurable settings.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (_definitions.isNotEmpty) ...[
                  _sectionTitle(context, 'Extension settings'),
                  ..._definitions.map(
                    (definition) => _buildSetting(context, definition),
                  ),
                ],
                if (domains.isNotEmpty && !hasScriptBaseUrl) ...[
                  _sectionTitle(context, 'Website address'),
                  RadioGroup<String>(
                    groupValue: _selectedDomain,
                    onChanged: (value) {
                      if (_saving || value == null) return;
                      setState(() => _selectedDomain = value);
                    },
                    child: Column(
                      children: domains
                          .map(
                            (domain) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(domain.name),
                              subtitle: Text(domain.url),
                              leading: Radio<String>(value: domain.url),
                              onTap: _saving
                                  ? null
                                  : () {
                                      setState(
                                        () => _selectedDomain = domain.url,
                                      );
                                    },
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ],
                if (_providers.isNotEmpty) ...[
                  _sectionTitle(context, 'Providers'),
                  ..._providers.map(
                    (provider) => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(provider.name),
                      subtitle: Text(provider.id),
                      value: _providerEnabled[provider.id] ?? true,
                      onChanged: _saving
                          ? null
                          : (value) {
                              setState(() {
                                _providerEnabled[provider.id] = value;
                              });
                            },
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save settings'),
                ),
              ],
            ),
    );
  }
}
