import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/plugin_config.dart';
import '../../providers/app_list_provider.dart';
import '../../providers/plugins_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/metadata/steam_connect_service.dart';
import 'steam_login_screen.dart';

const _pluginApiKeyLabels = <String, _ApiKeyInfo>{
  'metadata': _ApiKeyInfo(
    label: 'RAWG API Key',
    hint: 'Paste your rawg.io API key here',
    helpUrl: 'https://rawg.io/apidocs',
    helpText: 'Free key — register at rawg.io/apidocs',
  ),
  'steam_connect': _ApiKeyInfo(
    label: 'Steam Web API Key',
    hint: 'Paste your Steam Web API key',
    helpUrl: 'https://steamcommunity.com/dev/apikey',
    helpText: 'Get your key from steamcommunity.com/dev/apikey',
  ),
};

class _ApiKeyInfo {
  final String label;
  final String hint;
  final String helpUrl;
  final String helpText;

  const _ApiKeyInfo({
    required this.label,
    required this.hint,
    required this.helpUrl,
    required this.helpText,
  });
}

/// Full-screen edit page for a single plugin.
///
/// All text fields, toggles, and sliders use local state until the user
/// presses [Save]. [Cancel] / B discards any uncommitted changes.
class PluginEditScreen extends StatefulWidget {
  final PluginConfig plugin;

  const PluginEditScreen({super.key, required this.plugin});

  static Future<void> open(BuildContext context, PluginConfig plugin) {
    return Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => PluginEditScreen(plugin: plugin)),
    );
  }

  @override
  State<PluginEditScreen> createState() => _PluginEditScreenState();
}

class _PluginEditScreenState extends State<PluginEditScreen> {
  final _keyController = TextEditingController();
  final _steamIdController = TextEditingController();
  final _startupVideoController = TextEditingController();

  final _keyFocusNode = FocusNode(skipTraversal: true);
  final _steamIdFocusNode = FocusNode(skipTraversal: true);

  bool _loaded = false;
  bool _obscure = true;
  bool _isConnectingSteam = false;
  bool _showSteamAdvanced = false;
  String? _steamPersona;
  String _videoTrigger = 'before_app';

  // Local state that is only persisted on Save.
  late bool _enabled;
  late bool _microtrailerMuted;
  late int _videoDelaySeconds;
  double _screensaverTimeoutSec = 120;

  // Track whether any relevant provider-level value changed so we can
  // write it back on Save.
  bool _providerMicrotrailerChanged = false;
  bool _providerVideoDelayChanged = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.plugin.enabled;
    _load();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _steamIdController.dispose();
    _startupVideoController.dispose();
    _keyFocusNode.dispose();
    _steamIdFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final provider = context.read<PluginsProvider>();
    final key = await provider.getApiKey(widget.plugin.id);
    final steamId = await provider.getSetting(widget.plugin.id, 'steam_id');
    final steamPersona = await provider.getSetting(
      widget.plugin.id,
      'steam_persona',
    );
    final introVideoPath = await provider.getSetting(
      widget.plugin.id,
      'video_path',
    );
    final videoTrigger = await provider.getSetting(
      widget.plugin.id,
      'video_trigger',
    );
    final timeoutSec = await provider.getSetting(
      widget.plugin.id,
      'timeout_sec',
    );

    if (!mounted) return;
    setState(() {
      _keyController.text = key ?? '';
      _steamIdController.text = steamId ?? '';
      _startupVideoController.text = introVideoPath ?? '';
      _steamPersona = steamPersona;
      _videoTrigger = videoTrigger ?? 'before_app';
      _screensaverTimeoutSec = (double.tryParse(timeoutSec ?? '') ?? 120).clamp(
        30,
        600,
      );
      _microtrailerMuted = provider.microtrailerMuted;
      _videoDelaySeconds = provider.videoDelaySeconds;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final provider = context.read<PluginsProvider>();
    final appList = context.read<AppListProvider>();
    final enabledChanged = _enabled != widget.plugin.enabled;
    var metadataKeyChanged = false;
    var metadataKeyIsReady = false;

    // Persist enabled state if it changed.
    if (enabledChanged) {
      await provider.setEnabled(widget.plugin.id, enabled: _enabled);
    }

    // Persist API key if this plugin uses one.
    if (_pluginApiKeyLabels.containsKey(widget.plugin.id)) {
      final apiKey = _keyController.text.trim();
      final oldKey = await provider.getApiKey(widget.plugin.id) ?? '';
      if (apiKey != oldKey) {
        await provider.setApiKey(widget.plugin.id, apiKey);
        metadataKeyChanged = widget.plugin.id == 'metadata';
      }
      metadataKeyIsReady = widget.plugin.id == 'metadata' && apiKey.isNotEmpty;
    }

    // Steam Connect specific fields.
    if (widget.plugin.id == 'steam_connect') {
      final steamId = _steamIdController.text.trim();
      final oldSteamId =
          await provider.getSetting(widget.plugin.id, 'steam_id') ?? '';
      if (steamId != oldSteamId) {
        await provider.setSetting(widget.plugin.id, 'steam_id', steamId);
      }
    }

    // Startup intro video trigger.
    if (widget.plugin.id == 'startup_intro_video') {
      final oldTrigger =
          await provider.getSetting(widget.plugin.id, 'video_trigger') ??
          'before_app';
      if (_videoTrigger != oldTrigger) {
        await provider.setSetting(
          widget.plugin.id,
          'video_trigger',
          _videoTrigger,
        );
      }
      // video_path is saved immediately by the picker/restore button.
    }

    // Screensaver timeout.
    if (widget.plugin.id == 'screensaver') {
      final oldTimeout =
          await provider.getSetting(widget.plugin.id, 'timeout_sec') ?? '120';
      final newTimeout = _screensaverTimeoutSec.round().toString();
      if (newTimeout != oldTimeout) {
        await provider.setSetting(widget.plugin.id, 'timeout_sec', newTimeout);
      }
    }

    // Game video provider-level settings.
    if (widget.plugin.id == 'game_video') {
      if (_providerMicrotrailerChanged) {
        await provider.setMicrotrailerMuted(_microtrailerMuted);
      }
      if (_providerVideoDelayChanged) {
        await provider.setVideoDelaySeconds(_videoDelaySeconds);
      }
    }

    // Kick off metadata enrichment when a metadata plugin is enabled with a key.
    if (metadataKeyIsReady && (metadataKeyChanged || enabledChanged)) {
      unawaited(appList.triggerRawgArtworkRefresh());
    } else if (_enabled && mounted) {
      final apiKey = _keyController.text.trim();
      if (apiKey.isNotEmpty || widget.plugin.id == 'smart_genre_filters') {
        unawaited(appList.triggerMetadataEnrichment());
      }
    }

    if (mounted) Navigator.pop(context);
  }

  void _cancel() => Navigator.pop(context);

  Future<void> _pickStartupVideo() async {
    String? path;
    if (io.Platform.isAndroid || io.Platform.isIOS) {
      final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
      path = file?.path;
    } else {
      const videoGroup = XTypeGroup(
        label: 'Videos',
        extensions: ['mp4', 'mov', 'm4v', 'webm', 'mkv'],
      );
      final file = await openFile(acceptedTypeGroups: [videoGroup]);
      path = file?.path;
    }
    if (path == null || path.isEmpty) return;
    if (!mounted) return;

    _startupVideoController.text = path;
    final provider = context.read<PluginsProvider>();
    await provider.setSetting(widget.plugin.id, 'video_path', path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).pluginVideoSaved)),
    );
    setState(() {});
  }

  Future<void> _removeStartupVideo() async {
    _startupVideoController.clear();
    final provider = context.read<PluginsProvider>();
    await provider.setSetting(widget.plugin.id, 'video_path', '');
    setState(() {});
  }

  Future<void> _connectSteam() async {
    final apiKey = _keyController.text.trim();
    final steamId = _steamIdController.text.trim();

    if (steamId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).pluginSteamLoginFirst),
        ),
      );
      return;
    }

    if (apiKey.isEmpty) {
      await _connectSteamBasic(steamId);
      return;
    }

    setState(() => _isConnectingSteam = true);
    final info = await SteamConnectService().validateConnection(
      apiKey: apiKey,
      steamId: steamId,
    );
    if (!mounted) return;
    setState(() => _isConnectingSteam = false);

    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).pluginSteamValidationFailed,
          ),
        ),
      );
      return;
    }

    final provider = context.read<PluginsProvider>();
    await provider.setSetting(widget.plugin.id, 'steam_id', info.steamId);
    await provider.setSetting(
      widget.plugin.id,
      'steam_persona',
      info.personaName ?? '',
    );
    if (!provider.isEnabled(widget.plugin.id)) {
      await provider.setEnabled(widget.plugin.id, enabled: true);
      _enabled = true;
    }
    if (!mounted) return;
    setState(() {
      _steamIdController.text = info.steamId;
      _steamPersona = info.personaName;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          info.personaName == null
              ? '${AppLocalizations.of(context).pluginSteamConnectedMsg}.'
              : '${AppLocalizations.of(context).pluginSteamConnectedMsg}: ${info.personaName}',
        ),
      ),
    );
  }

  Future<void> _connectSteamBasic(String steamId) async {
    setState(() => _isConnectingSteam = true);
    final info = await SteamConnectService().fetchPublicProfile(steamId);
    if (!mounted) return;
    setState(() => _isConnectingSteam = false);

    final provider = context.read<PluginsProvider>();
    final persona = info?.personaName;
    if (persona != null && persona.isNotEmpty) {
      await provider.setSetting(widget.plugin.id, 'steam_persona', persona);
      if (mounted) setState(() => _steamPersona = persona);
    }
    if (!provider.isEnabled(widget.plugin.id)) {
      await provider.setEnabled(widget.plugin.id, enabled: true);
      _enabled = true;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            persona != null
                ? '${AppLocalizations.of(context).pluginSteamConnectedMsg}: $persona'
                : AppLocalizations.of(context).pluginSteamLinkedPrivate,
          ),
        ),
      );
    }
  }

  String _localizedName(BuildContext context) {
    final l = AppLocalizations.of(context);
    return switch (widget.plugin.id) {
      'steam_library_info' => l.steamLibraryInfoName,
      'metadata_enrichment' => l.pluginMetadataName,
      'rawg_trailer_video' => l.pluginVideoName,
      _ => widget.plugin.name,
    };
  }

  String _localizedDescription(BuildContext context) {
    final l = AppLocalizations.of(context);
    return switch (widget.plugin.id) {
      'steam_library_info' => l.steamLibraryInfoDesc,
      'metadata_enrichment' => l.pluginMetadataDesc,
      'rawg_trailer_video' => l.pluginVideoDesc,
      _ => widget.plugin.description,
    };
  }

  String _statusText(PluginsProvider provider) {
    final apiKeyInfo = _pluginApiKeyLabels[widget.plugin.id];
    final requiresMetadataReady = widget.plugin.id == 'smart_genre_filters';
    final requiresSteamReady = widget.plugin.id == 'steam_library_info';
    final requiresMetadataForDiscovery = widget.plugin.id == 'discovery_boost';
    final steamConnected = provider.isEnabled('steam_connect');
    final smartFiltersReady = provider.canUseSmartGenreFilters;

    if (requiresMetadataReady && !smartFiltersReady) {
      return 'Metadata + API key required';
    }
    if (requiresSteamReady && !steamConnected) {
      return 'Steam Connect required';
    }
    if (requiresMetadataForDiscovery && !provider.isEnabled('metadata')) {
      return 'Metadata plugin required';
    }
    if (apiKeyInfo != null && _keyController.text.isEmpty) {
      return 'API key required';
    }
    return 'Active';
  }

  bool _statusNeedsSetup(PluginsProvider provider) {
    final apiKeyInfo = _pluginApiKeyLabels[widget.plugin.id];
    final requiresMetadataReady = widget.plugin.id == 'smart_genre_filters';
    final requiresSteamReady = widget.plugin.id == 'steam_library_info';
    final requiresMetadataForDiscovery = widget.plugin.id == 'discovery_boost';
    final steamConnected = provider.isEnabled('steam_connect');
    final smartFiltersReady = provider.canUseSmartGenreFilters;

    return apiKeyInfo != null && _keyController.text.isEmpty ||
        requiresMetadataReady && !smartFiltersReady ||
        requiresSteamReady && !steamConnected ||
        requiresMetadataForDiscovery && !provider.isEnabled('metadata');
  }

  Color _categoryColor(PluginCategory cat) {
    return switch (cat) {
      PluginCategory.metadata => const Color(0xFF4FC3F7),
      PluginCategory.extraMetadata => const Color(0xFFCE93D8),
    };
  }

  String _categoryLabel(PluginCategory cat) {
    return switch (cat) {
      PluginCategory.metadata => 'METADATA',
      PluginCategory.extraMetadata => 'EXTRA METADATA',
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tp = context.watch<ThemeProvider>();
    final provider = context.watch<PluginsProvider>();
    final apiKeyInfo = _pluginApiKeyLabels[widget.plugin.id];

    if (!_loaded) {
      return Scaffold(
        backgroundColor: tp.background,
        appBar: AppBar(
          backgroundColor: tp.surface,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(_localizedName(context)),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final statusNeedsSetup = _statusNeedsSetup(provider);
    final statusColor = statusNeedsSetup ? Colors.amberAccent : tp.accentLight;
    final statusText = _statusText(provider);

    return Scaffold(
      backgroundColor: tp.background,
      appBar: AppBar(
        backgroundColor: tp.surface,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_localizedName(context)),
        leading: Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.gameButtonB ||
                event.logicalKey == LogicalKeyboardKey.escape) {
              _cancel();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _cancel,
          ),
        ),
      ),
      body: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.gameButtonB ||
              event.logicalKey == LogicalKeyboardKey.escape) {
            if (MediaQuery.viewInsetsOf(context).bottom > 0) {
              FocusManager.instance.primaryFocus?.unfocus();
            } else {
              _cancel();
            }
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: FocusTraversalGroup(
          // Deterministic top-to-bottom gamepad traversal through all controls
          // (toggle, fields, sliders, Cancel/Save), matching the Settings
          // screen. Combined with autofocus on the first control, this is what
          // lets the user navigate inside the feature page at all.
          policy: OrderedTraversalPolicy(),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: tp.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: tp.accent.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Icon(
                                _iconFor(widget.plugin.id),
                                color: tp.accentLight,
                                size: 30,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _localizedName(context),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _localizedDescription(context),
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 14,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      _categoryBadge(widget.plugin.category),
                                      const SizedBox(width: 10),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(
                                            alpha: 0.14,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              statusNeedsSetup
                                                  ? Icons.warning_amber_outlined
                                                  : Icons.check_circle_outline,
                                              color: statusColor,
                                              size: 15,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              statusText,
                                              style: TextStyle(
                                                color: statusColor,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 28),

                        // Enabled toggle
                        PluginFocusableToggle(
                          autofocus: true,
                          icon: _enabled ? Icons.power : Icons.power_off,
                          label: l.enabled,
                          value: _enabled,
                          onChanged: (v) => setState(() => _enabled = v),
                        ),

                        const SizedBox(height: 18),
                        const Divider(color: Colors.white12, height: 1),
                        const SizedBox(height: 18),

                        // API key fields (steam_connect handles its own key
                        // under the Advanced expander below).
                        if (apiKeyInfo != null &&
                            widget.plugin.id != 'steam_connect') ...[
                          PluginApiKeyField(
                            label: apiKeyInfo.label,
                            hint: apiKeyInfo.hint,
                            helpText: apiKeyInfo.helpText,
                            controller: _keyController,
                            focusNode: _keyFocusNode,
                            obscure: _obscure,
                            onToggleObscure: () =>
                                setState(() => _obscure = !_obscure),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 12),
                          if (widget.plugin.id == 'metadata')
                            PluginActionButton(
                              icon: Icons.open_in_new,
                              label: 'Get Key',
                              onTap: () => launchUrl(
                                Uri.parse('https://rawg.io/apidocs'),
                                mode: LaunchMode.externalApplication,
                              ),
                            ),
                          const SizedBox(height: 20),
                        ],

                        // Plugin-specific info blocks
                        if (widget.plugin.id == 'metadata')
                          _infoBlock(
                            Icons.warning_amber_rounded,
                            Colors.orangeAccent,
                            Localizations.localeOf(context).languageCode == 'es'
                                ? 'Es importante que los juegos tengan los nombres correctos en el servidor, o no se podrán obtener los metadatos.'
                                : 'Games must have their correct names on the server, otherwise metadata cannot be fetched.',
                          ),

                        if (widget.plugin.id == 'smart_genre_filters')
                          _infoBlock(
                            Icons.tips_and_updates_outlined,
                            Colors.cyanAccent,
                            Localizations.localeOf(context).languageCode == 'es'
                                ? 'Este plugin solo funciona cuando Metadata esta activo y la API key de RAWG ya esta configurada.'
                                : 'This plugin only works after Metadata is enabled and a RAWG API key has been configured.',
                          ),

                        if (widget.plugin.id == 'steam_library_info')
                          _infoBlock(
                            Icons.tips_and_updates_outlined,
                            Colors.cyanAccent,
                            Localizations.localeOf(context).languageCode == 'es'
                                ? 'Muestra datos de Steam en la ficha del juego: tiempo jugado, logros, reseñas, géneros y tráiler. También filtra por 100%, pendiente y nunca iniciado. Requiere Steam Connect activo con API key.'
                                : 'Shows Steam data in the game detail card: playtime, achievements, reviews, genres and trailer. Also filters by 100%, pending and never started. Requires Steam Connect with valid API key.',
                          ),

                        if (widget.plugin.id == 'discovery_boost')
                          _infoBlock(
                            Icons.tips_and_updates_outlined,
                            Colors.cyanAccent,
                            Localizations.localeOf(context).languageCode == 'es'
                                ? 'Sugerencias "similar a este juego" usando géneros/tags de metadata.'
                                : '“Similar to this game” recommendations using metadata genres/tags.',
                          ),

                        // Steam Connect — sign-in is the primary path: the
                        // webview login auto-extracts SteamID64 (and the web
                        // API key). Manual entry is demoted to Advanced.
                        if (widget.plugin.id == 'steam_connect') ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style:
                                  ElevatedButton.styleFrom(
                                    backgroundColor: tp.accent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 2,
                                    shadowColor: Colors.black26,
                                  ).copyWith(
                                    side: WidgetStateProperty.all(
                                      BorderSide.none,
                                    ),
                                    backgroundColor:
                                        WidgetStateProperty.resolveWith((
                                          states,
                                        ) {
                                          if (states.contains(
                                            WidgetState.focused,
                                          )) {
                                            return Color.lerp(
                                              tp.accent,
                                              Colors.white,
                                              0.15,
                                            );
                                          }
                                          return tp.accent;
                                        }),
                                  ),
                              icon: _isConnectingSteam
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.login, size: 20),
                              label: Text(
                                _isConnectingSteam
                                    ? l.pluginSteamConnecting
                                    : l.pluginSteamLogin,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              onPressed: _isConnectingSteam
                                  ? null
                                  : () async {
                                      final steamId =
                                          await SteamLoginScreen.show(context);
                                      if (steamId != null && mounted) {
                                        _steamIdController.text = steamId;
                                        await _connectSteam();
                                      }
                                    },
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            Localizations.localeOf(context).languageCode == 'es'
                                ? 'Inicia sesión y obtenemos tu SteamID y API key automáticamente.'
                                : 'Sign in and we grab your SteamID and API key automatically.',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                          if (_steamPersona != null &&
                              _steamPersona!.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.greenAccent,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${l.pluginSteamAccount}: $_steamPersona',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: () => setState(
                              () => _showSteamAdvanced = !_showSteamAdvanced,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showSteamAdvanced
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  size: 16,
                                  color: Colors.white38,
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'Advanced (manual SteamID / API key)',
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_showSteamAdvanced) ...[
                            const SizedBox(height: 12),
                            PluginApiKeyField(
                              label: 'SteamID64',
                              hint: 'SteamID64 (17 digits)',
                              helpText: '',
                              controller: _steamIdController,
                              focusNode: _steamIdFocusNode,
                              obscure: false,
                              onToggleObscure: () {},
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 12),
                            PluginApiKeyField(
                              label: apiKeyInfo!.label,
                              hint: apiKeyInfo.hint,
                              helpText: apiKeyInfo.helpText,
                              controller: _keyController,
                              focusNode: _keyFocusNode,
                              obscure: _obscure,
                              onToggleObscure: () =>
                                  setState(() => _obscure = !_obscure),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 12),
                            PluginActionButton(
                              icon: Icons.open_in_new,
                              label: 'Get Key',
                              onTap: () => launchUrl(
                                Uri.parse(
                                  'https://steamcommunity.com/dev/apikey',
                                ),
                                mode: LaunchMode.externalApplication,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                        ],

                        // Startup intro video
                        if (widget.plugin.id == 'startup_intro_video') ...[
                          Text(
                            l.pluginVideoHint,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _startupVideoController,
                            readOnly: true,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            decoration: InputDecoration(
                              hintText: 'No video selected',
                              hintStyle: const TextStyle(color: Colors.white30),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.04),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: Colors.white12,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: Colors.white12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: PluginActionButton(
                                  icon: Icons.video_file_outlined,
                                  label: l.pluginSelectVideo,
                                  onTap: _pickStartupVideo,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (_startupVideoController.text.isNotEmpty)
                                Expanded(
                                  child: PluginActionButton(
                                    icon: Icons.delete_outline,
                                    label: l.pluginRemove,
                                    accentColor: Colors.redAccent,
                                    onTap: _removeStartupVideo,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            l.pluginVideoWhen,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          PluginFocusableVideoTriggerOption(
                            label: l.pluginVideoTriggerApp,
                            selected: _videoTrigger == 'before_app',
                            onTap: () =>
                                setState(() => _videoTrigger = 'before_app'),
                          ),
                          const SizedBox(height: 8),
                          PluginFocusableVideoTriggerOption(
                            label: l.pluginVideoTriggerServer,
                            selected: _videoTrigger == 'before_server',
                            onTap: () =>
                                setState(() => _videoTrigger = 'before_server'),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Screensaver
                        if (widget.plugin.id == 'screensaver') ...[
                          PluginScreensaverTimeoutSlider(
                            value: _screensaverTimeoutSec,
                            onChanged: (v) =>
                                setState(() => _screensaverTimeoutSec = v),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Game video
                        if (widget.plugin.id == 'game_video') ...[
                          PluginFocusableToggle(
                            icon: _microtrailerMuted
                                ? Icons.volume_off
                                : Icons.volume_up,
                            label: l.pluginStartMuted,
                            value: _microtrailerMuted,
                            onChanged: (v) {
                              setState(() {
                                _microtrailerMuted = v;
                                _providerMicrotrailerChanged = true;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          PluginFocusableSlider(
                            icon: Icons.timer_outlined,
                            label: l.pluginVideoDelay,
                            value: _videoDelaySeconds.toDouble(),
                            min: 1,
                            max: 10,
                            step: 1,
                            suffix: 's',
                            onChanged: (v) {
                              setState(() {
                                _videoDelaySeconds = v.round();
                                _providerVideoDelayChanged = true;
                              });
                            },
                          ),
                          const SizedBox(height: 20),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom action bar
              Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  12 + MediaQuery.paddingOf(context).bottom,
                ),
                decoration: BoxDecoration(
                  color: tp.surface,
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: PluginActionButton(
                          icon: Icons.close,
                          label: l.cancel,
                          accentColor: Colors.white70,
                          onTap: _cancel,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: PluginActionButton(
                          icon: Icons.save,
                          label: l.save,
                          accentColor: tp.accentLight,
                          onTap: _save,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoBlock(IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryBadge(PluginCategory cat) {
    final color = _categoryColor(cat);
    final label = _categoryLabel(cat);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  static IconData _iconFor(String pluginId) {
    return switch (pluginId) {
      'steam_connect' => Icons.videogame_asset,
      'steam_library_info' => Icons.library_books,
      'metadata' => Icons.image_search,
      'smart_genre_filters' => Icons.filter_alt,
      'discovery_boost' => Icons.recommend,
      'game_video' => Icons.movie,
      'rawg_trailer_video' => Icons.play_circle_outline,
      'startup_intro_video' => Icons.smart_display,
      'screensaver' => Icons.bedtime,
      _ => Icons.extension,
    };
  }
}

class PluginActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accentColor;

  const PluginActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accentColor,
  });

  @override
  State<PluginActionButton> createState() => _PluginActionButtonState();
}

class _PluginActionButtonState extends State<PluginActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent =
        widget.accentColor ?? context.read<ThemeProvider>().accentLight;
    return Focus(
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.86,
            duration: const Duration(milliseconds: 220),
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.gameButtonA ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.select) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _focused
                ? accent.withValues(alpha: 0.24)
                : accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.20),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: _focused ? Colors.white : accent,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _focused ? Colors.white : accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

class PluginFocusableVideoTriggerOption extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const PluginFocusableVideoTriggerOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<PluginFocusableVideoTriggerOption> createState() =>
      _PluginFocusableVideoTriggerOptionState();
}

class _PluginFocusableVideoTriggerOptionState
    extends State<PluginFocusableVideoTriggerOption> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    return Focus(
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.92,
            duration: const Duration(milliseconds: 220),
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.gameButtonA ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.select) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: widget.selected
                ? tp.accent.withValues(alpha: _focused ? 0.28 : 0.18)
                : Colors.white.withValues(alpha: _focused ? 0.08 : 0.03),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                widget.selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: widget.selected ? tp.accentLight : Colors.white54,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: (_focused || widget.selected)
                        ? Colors.white
                        : Colors.white70,
                    fontSize: 13,
                    fontWeight: widget.selected
                        ? FontWeight.w700
                        : FontWeight.w500,
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

class PluginFocusableToggle extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool autofocus;

  const PluginFocusableToggle({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.autofocus = false,
  });

  @override
  State<PluginFocusableToggle> createState() => _PluginFocusableToggleState();
}

class _PluginFocusableToggleState extends State<PluginFocusableToggle> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.35,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select) {
          widget.onChanged(!widget.value);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () => widget.onChanged(!widget.value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _focused
                ? tp.accent.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                color: _focused ? Colors.white70 : Colors.white54,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: _focused ? Colors.white : Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ),
              ExcludeFocus(
                child: Switch(
                  value: widget.value,
                  activeThumbColor: tp.accent,
                  onChanged: (v) => widget.onChanged(v),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PluginFocusableSlider extends StatefulWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String suffix;
  final ValueChanged<double> onChanged;

  const PluginFocusableSlider({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.suffix,
    required this.onChanged,
  });

  @override
  State<PluginFocusableSlider> createState() => _PluginFocusableSliderState();
}

class _PluginFocusableSliderState extends State<PluginFocusableSlider> {
  bool _focused = false;
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
    final borderColor = _editing
        ? const Color(0xFF7CF7FF)
        : _focused
        ? tp.accent.withValues(alpha: 0.6)
        : Colors.transparent;

    return Focus(
      onFocusChange: (f) {
        setState(() {
          _focused = f;
          if (!f) _editing = false;
        });
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.35,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (_editing) {
          if (key == LogicalKeyboardKey.arrowLeft) {
            widget.onChanged(
              (widget.value - widget.step).clamp(widget.min, widget.max),
            );
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            widget.onChanged(
              (widget.value + widget.step).clamp(widget.min, widget.max),
            );
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.gameButtonB ||
              key == LogicalKeyboardKey.escape) {
            setState(() => _editing = false);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown) {
            return KeyEventResult.handled;
          }
        } else {
          if (key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.select) {
            setState(() => _editing = true);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () => setState(() => _editing = !_editing),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _editing
                ? Colors.white.withValues(alpha: 0.08)
                : _focused
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.transparent,
            border: (_focused || _editing)
                ? Border.all(color: borderColor, width: 1.5)
                : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    widget.icon,
                    color: _focused ? Colors.white70 : Colors.white54,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${widget.label}: ${widget.value.round()}${widget.suffix}',
                      style: TextStyle(
                        color: _focused ? Colors.white : Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (_editing)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7CF7FF).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF7CF7FF).withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Text(
                        '◀ ▶',
                        style: TextStyle(
                          color: Color(0xFF7CF7FF),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _editing
                      ? const Color(0xFF7CF7FF)
                      : tp.accentLight,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: _editing ? const Color(0xFF7CF7FF) : tp.accent,
                  overlayColor: tp.accent.withValues(alpha: 0.2),
                  trackHeight: 3,
                ),
                child: ExcludeFocus(
                  child: Slider(
                    value: widget.value,
                    min: widget.min,
                    max: widget.max,
                    divisions: ((widget.max - widget.min) / widget.step)
                        .round(),
                    label: '${widget.value.round()}${widget.suffix}',
                    onChanged: widget.onChanged,
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

class PluginScreensaverTimeoutSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const PluginScreensaverTimeoutSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<PluginScreensaverTimeoutSlider> createState() =>
      _PluginScreensaverTimeoutSliderState();
}

class _PluginScreensaverTimeoutSliderState
    extends State<PluginScreensaverTimeoutSlider> {
  bool _editing = false;
  bool _focused = false;

  static const double _min = 30;
  static const double _max = 600;
  static const double _step = 30;

  String get _label {
    final sec = widget.value.round();
    if (sec < 60) return '${sec}s';
    final min = sec ~/ 60;
    final rem = sec % 60;
    return rem == 0 ? '${min}m' : '${min}m ${rem}s';
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
    final isEs = Localizations.localeOf(context).languageCode == 'es';
    final borderColor = _editing
        ? const Color(0xFF7CF7FF)
        : _focused
        ? tp.accent.withValues(alpha: 0.6)
        : Colors.transparent;

    return Focus(
      onFocusChange: (f) {
        setState(() {
          _focused = f;
          if (!f) _editing = false;
        });
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (_editing) {
          if (key == LogicalKeyboardKey.arrowLeft) {
            widget.onChanged((widget.value - _step).clamp(_min, _max));
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            widget.onChanged((widget.value + _step).clamp(_min, _max));
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.gameButtonB ||
              key == LogicalKeyboardKey.escape) {
            setState(() => _editing = false);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown) {
            return KeyEventResult.handled;
          }
        } else {
          if (key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.select) {
            setState(() => _editing = true);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _editing
              ? Colors.white.withValues(alpha: 0.08)
              : _focused
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.transparent,
          border: (_focused || _editing)
              ? Border.all(color: borderColor, width: 1.5)
              : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.bedtime_outlined,
                  color: Colors.white54,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isEs
                        ? 'Tiempo de espera: $_label'
                        : 'Idle timeout: $_label',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                if (_editing)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7CF7FF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFF7CF7FF).withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Text(
                      '◀ ▶',
                      style: TextStyle(
                        color: Color(0xFF7CF7FF),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: _editing
                    ? const Color(0xFF7CF7FF)
                    : tp.accentLight,
                inactiveTrackColor: Colors.white12,
                thumbColor: _editing ? const Color(0xFF7CF7FF) : tp.accent,
                overlayColor: tp.accent.withValues(alpha: 0.2),
                trackHeight: 3,
              ),
              child: ExcludeFocus(
                child: Slider(
                  value: widget.value,
                  min: _min,
                  max: _max,
                  divisions: ((_max - _min) / _step).round(),
                  label: _label,
                  onChanged: widget.onChanged,
                ),
              ),
            ),
            Text(
              isEs
                  ? '30s – 10min · Presiona A para editar con ◀▶'
                  : '30s – 10min · Press A to edit with ◀▶',
              style: const TextStyle(color: Colors.white30, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class PluginApiKeyField extends StatefulWidget {
  final String label;
  final String hint;
  final String helpText;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  const PluginApiKeyField({
    super.key,
    required this.label,
    required this.hint,
    required this.helpText,
    required this.controller,
    required this.obscure,
    required this.onToggleObscure,
    required this.onChanged,
    this.focusNode,
  });

  @override
  State<PluginApiKeyField> createState() => _PluginApiKeyFieldState();
}

class _PluginApiKeyFieldState extends State<PluginApiKeyField> {
  bool _focused = false;
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
    return Focus(
      onFocusChange: (f) {
        setState(() {
          _focused = f;
          if (!f) _editing = false;
        });
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.35,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (!_editing &&
            (key == LogicalKeyboardKey.gameButtonA ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.select)) {
          setState(() => _editing = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.focusNode?.requestFocus();
            SystemChannels.textInput.invokeMethod('TextInput.show');
          });
          return KeyEventResult.handled;
        }

        if (_editing &&
            (key == LogicalKeyboardKey.gameButtonB ||
                key == LogicalKeyboardKey.escape)) {
          widget.focusNode?.unfocus();
          setState(() => _editing = false);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.all(_focused ? 10 : 0),
        decoration: BoxDecoration(
          color: _focused
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.transparent,
          border: _focused
              ? Border.all(
                  color: _editing
                      ? const Color(0xFF7CF7FF).withValues(alpha: 0.6)
                      : tp.accent.withValues(alpha: 0.6),
                  width: 1.5,
                )
              : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_focused && !_editing)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Ⓐ Edit',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (_editing)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7CF7FF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Ⓑ Done',
                      style: TextStyle(
                        color: Color(0xFF7CF7FF),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _editing = true);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  widget.focusNode?.requestFocus();
                  SystemChannels.textInput.invokeMethod('TextInput.show');
                });
              },
              child: ExcludeFocus(
                excluding: !_editing,
                child: IgnorePointer(
                  ignoring: !_editing,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    obscureText: widget.obscure,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      hintStyle: const TextStyle(
                        color: Colors.white24,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.04),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: tp.accent, width: 1.5),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          widget.obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                          color: Colors.white38,
                        ),
                        onPressed: widget.onToggleObscure,
                      ),
                    ),
                    onChanged: widget.onChanged,
                  ),
                ),
              ),
            ),
            if (widget.helpText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                widget.helpText,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
