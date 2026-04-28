import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_localizations.dart';
import '../../models/plugin_config.dart';
import '../../providers/app_list_provider.dart';
import '../../providers/plugins_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/metadata/steam_connect_service.dart';
import '../../services/tv/tv_detector.dart';
import '../../services/input/gamepad_button_helper.dart';
import '../companion/companion_qr_screen.dart';
import 'steam_login_screen.dart';

class PluginsScreen extends StatelessWidget {
  const PluginsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tp = context.watch<ThemeProvider>();
    return Scaffold(
      backgroundColor: tp.background,
      appBar: AppBar(
        title: Text(
          l.plugins,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: tp.surface,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack ||
              key == LogicalKeyboardKey.gameButtonB) {
            if (MediaQuery.viewInsetsOf(context).bottom > 0) {
              FocusManager.instance.primaryFocus?.unfocus();
            } else {
              Navigator.maybePop(context);
            }
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            if (TvDetector.instance.isTV)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tp.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.qr_code_2, size: 22),
                    label: Text(
                      l.configureFromPhoneBtn,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    onPressed: () => CompanionQrScreen.show(context),
                  ),
                ),
              ),
            if (TvDetector.instance.isTV) const SizedBox(height: 12),
            Expanded(
              child: Consumer<PluginsProvider>(
                builder: (context, provider, _) {
                  final plugins = provider.plugins
                      .where((p) => p.id != 'discovery_boost')
                      .toList();
                  return ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      550 + MediaQuery.paddingOf(context).bottom,
                    ),
                    itemCount: plugins.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _PluginCard(plugin: plugins[index]),
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

class _PluginCard extends StatefulWidget {
  const _PluginCard({required this.plugin});

  final PluginConfig plugin;

  @override
  State<_PluginCard> createState() => _PluginCardState();
}

class _PluginCardState extends State<_PluginCard> {
  final _keyController = TextEditingController();
  final _steamIdController = TextEditingController();
  final _startupVideoController = TextEditingController();

  late final FocusNode _keyFocusNode;
  late final FocusNode _steamIdFocusNode;
  late final FocusNode _videPathFocusNode;
  bool _keyLoaded = false;
  bool _obscure = true;
  bool _isConnectingSteam = false;
  String? _steamPersona;
  String _videoTrigger = 'before_app';
  bool _cardFocused = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();

    _keyFocusNode = FocusNode(skipTraversal: true);
    _steamIdFocusNode = FocusNode(skipTraversal: true);
    _videPathFocusNode = FocusNode(skipTraversal: true);
    _loadApiKey();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _steamIdController.dispose();
    _startupVideoController.dispose();
    _keyFocusNode.dispose();
    _steamIdFocusNode.dispose();
    _videPathFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadApiKey() async {
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
    if (!mounted) return;
    setState(() {
      _keyController.text = key ?? '';
      _steamIdController.text = steamId ?? '';
      _startupVideoController.text = introVideoPath ?? '';
      _steamPersona = steamPersona;
      _videoTrigger = videoTrigger ?? 'before_app';
      _keyLoaded = true;
    });
  }

  Future<void> _saveApiKey(String value) async {
    final provider = context.read<PluginsProvider>();
    await provider.setApiKey(widget.plugin.id, value.trim());
    if (value.trim().isNotEmpty && mounted) {
      context.read<AppListProvider>().triggerMetadataEnrichment();
    }
  }

  Future<void> _saveSteamId(String value) async {
    final provider = context.read<PluginsProvider>();
    await provider.setSetting(widget.plugin.id, 'steam_id', value.trim());
  }

  Future<void> _saveVideoTrigger(String value) async {
    setState(() => _videoTrigger = value);
    final provider = context.read<PluginsProvider>();
    await provider.setSetting(widget.plugin.id, 'video_trigger', value);
  }

  Future<void> _pickStartupVideo() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mov', 'm4v', 'webm', 'mkv'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final path = file.path;
    if (path == null || path.isEmpty) return;
    if (!mounted) return;

    _startupVideoController.text = path;
    final provider = context.read<PluginsProvider>();
    await provider.setSetting(widget.plugin.id, 'video_path', path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).pluginVideoSaved)),
    );
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PluginsProvider>();
    final tc = context.read<ThemeProvider>();
    final isEnabled = widget.plugin.enabled;
    final apiKeyInfo = _pluginApiKeyLabels[widget.plugin.id];
    final requiresMetadataReady = widget.plugin.id == 'smart_genre_filters';
    final requiresSteamReady = widget.plugin.id == 'steam_library_info';
    final requiresMetadataForDiscovery = widget.plugin.id == 'discovery_boost';
    final steamConnected = provider.isEnabled('steam_connect');
    final smartFiltersReady = provider.canUseSmartGenreFilters;
    final statusNeedsSetup =
        apiKeyInfo != null && _keyController.text.isEmpty ||
        requiresMetadataReady && !smartFiltersReady ||
        requiresSteamReady && !steamConnected ||
        requiresMetadataForDiscovery && !provider.isEnabled('metadata');
    final statusIcon = statusNeedsSetup
        ? Icons.warning_amber_outlined
        : Icons.check_circle_outline;
    final statusColor = statusNeedsSetup ? Colors.amberAccent : tc.accentLight;
    final statusText = requiresMetadataReady && !smartFiltersReady
        ? 'Metadata + API key required'
        : requiresSteamReady && !steamConnected
        ? 'Steam Connect required'
        : requiresMetadataForDiscovery && !provider.isEnabled('metadata')
        ? 'Metadata plugin required'
        : apiKeyInfo != null && _keyController.text.isEmpty
        ? 'API key required'
        : 'Active';

    return Focus(
      onFocusChange: (focused) {
        setState(() => _cardFocused = focused);
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.35,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (node.hasPrimaryFocus) {
          if (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.gameButtonA) {
            setState(() => _expanded = !_expanded);
            return KeyEventResult.handled;
          }

          if (key == LogicalKeyboardKey.gameButtonX) {
            final newState = !widget.plugin.enabled;
            provider.setEnabled(widget.plugin.id, enabled: newState);
            if (newState && context.mounted) {
              context.read<AppListProvider>().triggerMetadataEnrichment();
            }
            if (newState && !_expanded) setState(() => _expanded = true);
            return KeyEventResult.handled;
          }

          if (_expanded && isEnabled && key == LogicalKeyboardKey.arrowDown) {
            for (final d in node.descendants) {
              if (d.canRequestFocus && !d.skipTraversal) {
                d.requestFocus();
                return KeyEventResult.handled;
              }
            }
          }
          return KeyEventResult.ignored;
        }

        if (key == LogicalKeyboardKey.gameButtonB ||
            key == LogicalKeyboardKey.escape) {
          node.requestFocus();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              Scrollable.ensureVisible(
                context,
                alignment: 0.35,
                duration: const Duration(milliseconds: 200),
              );
            }
          });
          return KeyEventResult.handled;
        }

        if (key == LogicalKeyboardKey.arrowUp) {
          final focusedChild = node.descendants
              .where((d) => d.hasPrimaryFocus)
              .firstOrNull;
          final firstFocusable = node.descendants
              .where((d) => d.canRequestFocus && !d.skipTraversal)
              .firstOrNull;
          if (focusedChild != null && focusedChild == firstFocusable) {
            node.requestFocus();
            return KeyEventResult.handled;
          }
        }

        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: _expanded ? null : const BoxConstraints(minHeight: 60),
        decoration: BoxDecoration(
          color: _cardFocused ? tc.surfaceVariant : tc.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: _cardFocused
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.15),
              blurRadius: _cardFocused ? 10 : 6,
              offset: Offset(0, _cardFocused ? 4 : 2),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, _expanded ? 40 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _localizedName(context),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          _categoryBadge(widget.plugin.category),
                        ],
                      ),
                    ),

                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        color: _cardFocused ? Colors.white : Colors.white38,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 4),

                    ExcludeFocus(
                      child: Switch(
                        value: isEnabled,
                        activeThumbColor: tc.accent,
                        onChanged: (v) {
                          provider.setEnabled(widget.plugin.id, enabled: v);
                          if (v && context.mounted) {
                            context
                                .read<AppListProvider>()
                                .triggerMetadataEnrichment();

                            if (!_expanded) setState(() => _expanded = true);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (_expanded) ...[
                const SizedBox(height: 12),
                Text(
                  _localizedDescription(context),
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],

              if (_cardFocused)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      GamepadHintIcon('A', size: 14),
                      const SizedBox(width: 3),
                      Text(
                        _expanded ? 'Collapse' : 'Expand',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 9,
                        ),
                      ),
                      const SizedBox(width: 10),
                      GamepadHintIcon('X', size: 14),
                      const SizedBox(width: 3),
                      Text(
                        isEnabled ? 'Disable' : 'Enable',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              if (isEnabled) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tc.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, color: statusColor, size: 15),
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
              if (isEnabled && _expanded) ...[
                FocusTraversalGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),

                      if (apiKeyInfo != null && _keyLoaded) ...[
                        _ApiKeyField(
                          label: apiKeyInfo.label,
                          hint: apiKeyInfo.hint,
                          helpText: apiKeyInfo.helpText,
                          controller: _keyController,
                          focusNode: _keyFocusNode,
                          obscure: _obscure,
                          onToggleObscure: () =>
                              setState(() => _obscure = !_obscure),
                          onChanged: _saveApiKey,
                        ),
                        const SizedBox(height: 8),
                        // "Get Key" hyperlink below the API key field
                        if (widget.plugin.id == 'metadata')
                          _PluginActionButton(
                            icon: Icons.open_in_new,
                            label: 'Get Key',
                            onTap: () => launchUrl(
                              Uri.parse('https://rawg.io/apidocs'),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                        if (widget.plugin.id == 'steam_connect')
                          _PluginActionButton(
                            icon: Icons.open_in_new,
                            label: 'Get Key',
                            onTap: () => launchUrl(
                              Uri.parse(
                                'https://steamcommunity.com/dev/apikey',
                              ),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                        const SizedBox(height: 12),
                      ],

                      if (widget.plugin.id == 'metadata')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orangeAccent,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  Localizations.localeOf(
                                            context,
                                          ).languageCode ==
                                          'es'
                                      ? 'Es importante que los juegos tengan los nombres correctos en el servidor, o no se podrán obtener los metadatos.'
                                      : 'Games must have their correct names on the server, otherwise metadata cannot be fetched.',
                                  style: const TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (widget.plugin.id == 'smart_genre_filters')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.tips_and_updates_outlined,
                                color: Colors.cyanAccent,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  Localizations.localeOf(
                                            context,
                                          ).languageCode ==
                                          'es'
                                      ? 'Este plugin solo funciona cuando Metadata esta activo y la API key de RAWG ya esta configurada.'
                                      : 'This plugin only works after Metadata is enabled and a RAWG API key has been configured.',
                                  style: const TextStyle(
                                    color: Colors.cyanAccent,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (widget.plugin.id == 'steam_library_info')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            Localizations.localeOf(context).languageCode == 'es'
                                ? 'Muestra datos de Steam en la ficha del juego: tiempo jugado, logros, reseñas, géneros y tráiler. También filtra por 100%, pendiente y nunca iniciado. Requiere Steam Connect activo con API key.'
                                : 'Shows Steam data in the game detail card: playtime, achievements, reviews, genres and trailer. Also filters by 100%, pending and never started. Requires Steam Connect with valid API key.',
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      if (widget.plugin.id == 'discovery_boost')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            Localizations.localeOf(context).languageCode == 'es'
                                ? 'Sugerencias "similar a este juego" usando géneros/tags de metadata.'
                                : '“Similar to this game” recommendations using metadata genres/tags.',
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      if (widget.plugin.id == 'steam_connect' &&
                          _keyLoaded) ...[
                        const SizedBox(height: 12),

                        _ApiKeyField(
                          label: 'SteamID64',
                          hint: 'SteamID64 (17 digits)',
                          helpText: '',
                          controller: _steamIdController,
                          focusNode: _steamIdFocusNode,
                          obscure: false,
                          onToggleObscure: () {},
                          onChanged: _saveSteamId,
                        ),
                        const SizedBox(height: 12),

                        ElevatedButton.icon(
                          style:
                              ElevatedButton.styleFrom(
                                backgroundColor: tc.surfaceVariant,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 2,
                                shadowColor: Colors.black26,
                              ).copyWith(
                                side: WidgetStateProperty.all(BorderSide.none),
                                backgroundColor:
                                    WidgetStateProperty.resolveWith((states) {
                                      if (states.contains(
                                        WidgetState.focused,
                                      )) {
                                        return Color.lerp(
                                          tc.surfaceVariant,
                                          Colors.white,
                                          0.10,
                                        );
                                      }
                                      return tc.surfaceVariant;
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
                              : const Icon(Icons.open_in_browser, size: 18),
                          label: Text(
                            _isConnectingSteam
                                ? AppLocalizations.of(
                                    context,
                                  ).pluginSteamConnecting
                                : AppLocalizations.of(context).pluginSteamLogin,
                          ),
                          onPressed: _isConnectingSteam
                              ? null
                              : () async {
                                  final steamId = await SteamLoginScreen.show(
                                    context,
                                  );
                                  if (steamId != null && mounted) {
                                    _steamIdController.text = steamId;
                                    await _saveSteamId(steamId);
                                    await _connectSteam();
                                  }
                                },
                        ),
                        if (_steamPersona != null &&
                            _steamPersona!.isNotEmpty) ...[
                          const SizedBox(height: 8),
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
                                  '${AppLocalizations.of(context).pluginSteamAccount}: $_steamPersona',
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
                      ],
                      if (widget.plugin.id == 'startup_intro_video' &&
                          _keyLoaded) ...[
                        const SizedBox(height: 12),
                        Text(
                          AppLocalizations.of(context).pluginVideoHint,
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
                          focusNode: FocusNode(skipTraversal: true),
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
                              child: _PluginActionButton(
                                icon: Icons.video_file_outlined,
                                label: AppLocalizations.of(
                                  context,
                                ).pluginSelectVideo,
                                onTap: _pickStartupVideo,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_startupVideoController.text.isNotEmpty)
                              Expanded(
                                child: _PluginActionButton(
                                  icon: Icons.delete_outline,
                                  label: AppLocalizations.of(
                                    context,
                                  ).pluginRemove,
                                  accentColor: Colors.redAccent,
                                  onTap: () async {
                                    _startupVideoController.clear();
                                    final provider = context
                                        .read<PluginsProvider>();
                                    await provider.setSetting(
                                      widget.plugin.id,
                                      'video_path',
                                      '',
                                    );
                                    if (!mounted) return;
                                    setState(() {});
                                  },
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          AppLocalizations.of(context).pluginVideoWhen,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _FocusableVideoTriggerOption(
                          label: AppLocalizations.of(
                            context,
                          ).pluginVideoTriggerApp,
                          selected: _videoTrigger == 'before_app',
                          onTap: () => _saveVideoTrigger('before_app'),
                        ),
                        const SizedBox(height: 8),
                        _FocusableVideoTriggerOption(
                          label: AppLocalizations.of(
                            context,
                          ).pluginVideoTriggerServer,
                          selected: _videoTrigger == 'before_server',
                          onTap: () => _saveVideoTrigger('before_server'),
                        ),
                        const SizedBox(height: 18),
                      ],

                      if (widget.plugin.id == 'screensaver') ...[
                        const SizedBox(height: 12),
                        _ScreensaverTimeoutSlider(pluginId: widget.plugin.id),
                      ],

                      if (widget.plugin.id == 'game_video') ...[
                        const SizedBox(height: 12),
                        _FocusableToggle(
                          icon: provider.microtrailerMuted
                              ? Icons.volume_off
                              : Icons.volume_up,
                          label: AppLocalizations.of(context).pluginStartMuted,
                          value: provider.microtrailerMuted,
                          onChanged: (v) => provider.setMicrotrailerMuted(v),
                        ),
                        const SizedBox(height: 12),
                        _FocusableSlider(
                          icon: Icons.timer_outlined,
                          label: AppLocalizations.of(context).pluginVideoDelay,
                          value: provider.videoDelaySeconds.toDouble(),
                          min: 1,
                          max: 10,
                          step: 1,
                          suffix: 's',
                          onChanged: (v) =>
                              provider.setVideoDelaySeconds(v.round()),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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

  Color _categoryColor(PluginCategory cat) {
    return switch (cat) {
      PluginCategory.metadata => const Color(0xFF4FC3F7),
      PluginCategory.extraMetadata => const Color(0xFFCE93D8),
    };
  }

  Widget _categoryBadge(PluginCategory cat) {
    final label = switch (cat) {
      PluginCategory.metadata => 'METADATA',
      PluginCategory.extraMetadata => 'EXTRA METADATA',
    };
    final color = _categoryColor(cat);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
}

class _PluginActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accentColor;

  const _PluginActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accentColor,
  });

  @override
  State<_PluginActionButton> createState() => _PluginActionButtonState();
}

class _PluginActionButtonState extends State<_PluginActionButton> {
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

class _FocusableVideoTriggerOption extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FocusableVideoTriggerOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_FocusableVideoTriggerOption> createState() =>
      _FocusableVideoTriggerOptionState();
}

class _FocusableVideoTriggerOptionState
    extends State<_FocusableVideoTriggerOption> {
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

class _FocusableToggle extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _FocusableToggle({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_FocusableToggle> createState() => _FocusableToggleState();
}

class _FocusableToggleState extends State<_FocusableToggle> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
    return Focus(
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

class _FocusableSlider extends StatefulWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String suffix;
  final ValueChanged<double> onChanged;

  const _FocusableSlider({
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
  State<_FocusableSlider> createState() => _FocusableSliderState();
}

class _FocusableSliderState extends State<_FocusableSlider> {
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

class _ScreensaverTimeoutSlider extends StatefulWidget {
  const _ScreensaverTimeoutSlider({required this.pluginId});
  final String pluginId;

  @override
  State<_ScreensaverTimeoutSlider> createState() =>
      _ScreensaverTimeoutSliderState();
}

class _ScreensaverTimeoutSliderState extends State<_ScreensaverTimeoutSlider> {
  double _timeoutSec = 120;
  bool _loaded = false;
  bool _editing = false;
  bool _focused = false;

  static const double _min = 30;
  static const double _max = 600;
  static const double _step = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<PluginsProvider>();
    final saved = await provider.getSetting(widget.pluginId, 'timeout_sec');
    if (!mounted) return;
    setState(() {
      _timeoutSec = (double.tryParse(saved ?? '') ?? 120).clamp(_min, _max);
      _loaded = true;
    });
  }

  Future<void> _save(double value) async {
    final clamped = value.clamp(_min, _max);
    setState(() => _timeoutSec = clamped);
    final provider = context.read<PluginsProvider>();
    await provider.setSetting(
      widget.pluginId,
      'timeout_sec',
      clamped.round().toString(),
    );
  }

  String get _label {
    final sec = _timeoutSec.round();
    if (sec < 60) return '${sec}s';
    final min = sec ~/ 60;
    final rem = sec % 60;
    return rem == 0 ? '${min}m' : '${min}m ${rem}s';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
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
            _save((_timeoutSec - _step).clamp(_min, _max));
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            _save((_timeoutSec + _step).clamp(_min, _max));
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
                  value: _timeoutSec,
                  min: _min,
                  max: _max,
                  divisions: ((_max - _min) / _step).round(),
                  label: _label,
                  onChanged: _save,
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

class _ApiKeyField extends StatefulWidget {
  const _ApiKeyField({
    required this.label,
    required this.hint,
    required this.helpText,
    required this.controller,
    required this.obscure,
    required this.onToggleObscure,
    required this.onChanged,
    this.focusNode,
  });

  final String label;
  final String hint;
  final String helpText;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  @override
  State<_ApiKeyField> createState() => _ApiKeyFieldState();
}

class _ApiKeyFieldState extends State<_ApiKeyField> {
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
          widget.focusNode?.requestFocus();
          WidgetsBinding.instance.addPostFrameCallback((_) {
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
            ExcludeFocus(
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
            const SizedBox(height: 4),
            Text(
              widget.helpText,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusableTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final ValueChanged<String> onChanged;

  const _FocusableTextField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.onChanged,
  });

  @override
  State<_FocusableTextField> createState() => _FocusableTextFieldState();
}

class _FocusableTextFieldState extends State<_FocusableTextField> {
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
          widget.focusNode.requestFocus();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            SystemChannels.textInput.invokeMethod('TextInput.show');
          });
          return KeyEventResult.handled;
        }
        if (_editing &&
            (key == LogicalKeyboardKey.gameButtonB ||
                key == LogicalKeyboardKey.escape)) {
          widget.focusNode.unfocus();
          setState(() => _editing = false);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
          borderRadius: BorderRadius.circular(10),
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
            const SizedBox(height: 4),
            ExcludeFocus(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: const TextStyle(color: Colors.white30),
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
                ),
                onChanged: widget.onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
