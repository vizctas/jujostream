import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_localizations.dart';
import '../../models/stream_configuration.dart';
import '../../models/theme_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/plugins_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/input/gamepad_button_helper.dart';
import '../../services/tv/tv_detector.dart';
import '../../services/window/fullscreen_service.dart';
import '../../services/preferences/launcher_preferences.dart';
import '../about/about_screen.dart';
import '../collections/collections_screen.dart';
import '../plugins/plugins_screen.dart';
import 'device_flow_screen.dart';
import '../../themes/launcher_theme.dart';
import '../../themes/launcher_theme_registry.dart';
import '../../widgets/coming_soon_dialog.dart';
import 'vpn_guide_sheet.dart';

// Top-level translation helper — accessible from all widget classes in this file.
String _tr(BuildContext context, String en, String es) {
  return AppLocalizations.of(context).locale.languageCode == 'es' ? es : en;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  static const int _kTabCount = 5;
  late final TabController _tabController;
  final List<FocusScopeNode> _tabScopes = List.generate(
    _kTabCount,
    (i) => FocusScopeNode(debugLabel: 'settings-tab-$i'),
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _kTabCount, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    for (final s in _tabScopes) {
      s.dispose();
    }
    super.dispose();
  }

  void _cycleTab(int delta) {
    if (_tabController.indexIsChanging) return;
    final next = (_tabController.index + delta + _kTabCount) % _kTabCount;
    _tabController.animateTo(next);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final scope = _tabScopes[_tabController.index];
    scope.focusedChild?.unfocus(disposition: UnfocusDisposition.scope);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final first = scope.traversalDescendants
          .where((n) => n.canRequestFocus && !n.skipTraversal)
          .firstOrNull;
      if (first != null) {
        first.requestFocus();
      } else {
        scope.requestFocus();
      }
    });
  }

  void _scrollToTop(BuildContext context) {
    final scroll = PrimaryScrollController.of(context);
    if (scroll.hasClients) {
      scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tp = context.watch<ThemeProvider>();
    final bg = tp.background;
    final cardBg = tp.surface;
    final prefs = context.watch<LauncherPreferences>();

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.gameButtonB ||
            key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack) {
          Navigator.maybePop(context);
          return KeyEventResult.handled;
        }
        // RB / R1 — next tab (wraps)
        if (key == LogicalKeyboardKey.gameButtonRight1) {
          _cycleTab(1);
          return KeyEventResult.handled;
        }
        // LB / L1 — prev tab (wraps)
        if (key == LogicalKeyboardKey.gameButtonLeft1) {
          _cycleTab(-1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: Text(
            l.settings,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: cardBg,
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Row(
              children: [
                if (prefs.showButtonHints)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 6),
                    child: _TabHintChip(
                      label: prefs.buttonScheme == 'playstation' ? 'L1' : 'LB',
                    ),
                  ),
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    padding: EdgeInsets.zero,
                    tabAlignment: TabAlignment.start,
                    indicator: const BoxDecoration(),
                    dividerColor: Colors.transparent,
                    indicatorColor: Colors.transparent,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.normal,
                    ),
                    tabs: [
                      Tab(
                        text: _tr(
                          context,
                          'Personalization',
                          'Personalización',
                        ),
                      ),
                      Tab(text: _tr(context, 'Video & Audio', 'Video y Audio')),
                      Tab(text: _tr(context, 'Controller', 'Mando')),
                      Tab(text: _tr(context, 'Desktop', 'Escritorio')),
                      Tab(text: _tr(context, 'Labs', 'Laboratorios')),
                    ],
                  ),
                ),
                if (prefs.showButtonHints)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: _TabHintChip(
                      label: prefs.buttonScheme == 'playstation' ? 'R1' : 'RB',
                    ),
                  ),
              ],
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Consumer<SettingsProvider>(
            builder: (context, settings, _) {
              final c = settings.config;
              final themeProvider = context.watch<ThemeProvider>();
              final preferences = context.watch<LauncherPreferences>();

              return TabBarView(
                controller: _tabController,
                children: [
                  FocusScope(
                    node: _tabScopes[0],
                    child: FocusTraversalGroup(
                      policy: OrderedTraversalPolicy(),
                      child: ListView(
                        padding: const EdgeInsets.only(top: 16, bottom: 160),
                        children: [
                          _buildAccountCard(context),
                          const SizedBox(height: 4),

                          _section(_tr(context, 'Appearance', 'Apariencia')),
                          _CollapsableSection(
                            title: _tr(
                              context,
                              'Layout Theme',
                              'Tema de interfaz',
                            ),
                            icon: Icons.dashboard_outlined,
                            child: _buildLauncherThemePicker(
                              context,
                              themeProvider,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _CollapsableSection(
                            title: _tr(
                              context,
                              'Color Scheme',
                              'Esquema de color',
                            ),
                            icon: Icons.palette_outlined,
                            child: _buildThemeSelector(context, themeProvider),
                          ),

                          _section(_tr(context, 'Ambience', 'Ambiente')),
                          _choiceTile(
                            context,
                            _tr(
                              context,
                              'Ambience Layout',
                              'Diseño de ambiente',
                            ),
                            themeProvider.ambienceLayout == 'circular'
                                ? _tr(context, 'Circular', 'Circular')
                                : _tr(context, 'Card', 'Tarjeta'),
                            () => _pickAmbienceLayout(context, themeProvider),
                          ),
                          _choiceTile(
                            context,
                            _tr(
                              context,
                              'Background Effect',
                              'Efecto de fondo',
                            ),
                            themeProvider.ambienceEffect == 'particles'
                                ? _tr(context, 'Particles', 'Partículas')
                                : (themeProvider.ambienceEffect == 'waves'
                                      ? _tr(context, 'Waves', 'Ondas')
                                      : _tr(context, 'None', 'Ninguno')),
                            () => _pickAmbienceEffect(context, themeProvider),
                          ),
                          _choiceTile(
                            context,
                            _tr(context, 'Stand-by sound', 'Sonido de espera'),
                            themeProvider.standbySound,
                            () => _pickStandbySound(context, themeProvider),
                          ),

                          _section('Language / Idioma'),
                          _buildLanguageTile(context),

                          _section(
                            _tr(
                              context,
                              'Performance & Quality',
                              'Rendimiento y calidad',
                            ),
                          ),
                          _toggle(
                            _tr(context, 'Reduce Effects', 'Reducir efectos'),
                            _tr(
                              context,
                              'Disable Ken Burns, palette extraction, video previews',
                              'Desactiva Ken Burns, extracción de paleta y vistas previas de video',
                            ),
                            themeProvider.reduceEffects,
                            (v) => themeProvider.setReduceEffects(v),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Performance Mode',
                              'Modo rendimiento',
                            ),
                            _tr(
                              context,
                              'Reduce effects + lower quality defaults for weak devices',
                              'Reduce efectos y baja la calidad por defecto en dispositivos débiles',
                            ),
                            themeProvider.performanceMode,
                            (v) => themeProvider.setPerformanceMode(v),
                          ),
                          _choiceTile(
                            context,
                            _tr(context, 'Visual Quality', 'Calidad visual'),
                            _artQualityLabel(context, themeProvider.artQuality),
                            () => _pickArtQuality(context, themeProvider),
                          ),
                          _buildKofiSection(context),
                        ],
                      ),
                    ),
                  ),
                  FocusScope(
                    node: _tabScopes[1],
                    child: FocusTraversalGroup(
                      policy: OrderedTraversalPolicy(),
                      child: ListView(
                        padding: const EdgeInsets.only(top: 16, bottom: 160),
                        children: [
                          _section(_tr(context, 'Video', 'Video')),
                          _choiceTile(
                            context,
                            _tr(context, 'Resolution', 'Resolución'),
                            _resLabel(c),
                            () => _pickResolution(context, settings, c),
                          ),
                          Builder(
                            builder: (ctx) {
                              final mq = MediaQuery.of(ctx);
                              final dpr = mq.devicePixelRatio;
                              return _CustomResolutionTile(
                                currentWidth: c.width,
                                currentHeight: c.height,
                                matchDisplayWidth: (mq.size.width * dpr)
                                    .round(),
                                matchDisplayHeight: (mq.size.height * dpr)
                                    .round(),
                                onApply: (w, h) => settings.setResolution(w, h),
                              );
                            },
                          ),
                          _choiceTile(
                            context,
                            _tr(context, 'Frame Rate', 'Frecuencia de cuadros'),
                            '${c.fps} FPS',
                            () => _pickFps(context, settings, c),
                          ),
                          _toggle(
                            l.smartBitrate,
                            l.smartBitrateDesc,
                            c.smartBitrateEnabled,
                            (v) {
                              settings.updateConfig(
                                c.copyWith(smartBitrateEnabled: v),
                              );
                              if (v) _showSmartBitrateDisclaimer(context);
                            },
                          ),
                          if (c.smartBitrateEnabled) ...[
                            _sliderTile(
                              '  ${l.smartBitrateMin}',
                              '${c.smartBitrateMin ~/ 1000} Mbps',
                              c.smartBitrateMin.toDouble(),
                              5000,
                              80000,
                              75,
                              (v) => settings.updateConfig(
                                c.copyWith(smartBitrateMin: v.toInt()),
                              ),
                            ),
                            _sliderTile(
                              '  ${l.smartBitrateMax}',
                              '${c.smartBitrateMax ~/ 1000} Mbps',
                              c.smartBitrateMax.toDouble(),
                              5000,
                              150000,
                              145,
                              (v) => settings.updateConfig(
                                c.copyWith(smartBitrateMax: v.toInt()),
                              ),
                            ),
                          ],
                          if (!c.smartBitrateEnabled)
                            _sliderTile(
                              _tr(context, 'Manual Bitrate', 'Bitrate manual'),
                              '${c.bitrate ~/ 1000} Mbps',
                              c.bitrate.toDouble(),
                              1000,
                              150000,
                              149,
                              (v) => settings.updateConfig(
                                c.copyWith(bitrate: v.toInt()),
                              ),
                            ),
                          _choiceTile(
                            context,
                            _tr(context, 'Video Codec', 'Códec de video'),
                            _codecLabel(context, c.videoCodec),
                            () => _pickCodec(context, settings, c),
                          ),
                          _choiceTile(
                            context,
                            _tr(context, 'Scale Mode', 'Modo de escala'),
                            _scaleLabel(context, c.scaleMode),
                            () => _pickScaleMode(context, settings, c),
                          ),
                          _choiceTile(
                            context,
                            _tr(
                              context,
                              'Frame Pacing',
                              'Sincronización de frames',
                            ),
                            _pacingLabel(context, c.framePacing),
                            () => _pickFramePacing(context, settings, c),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Ultra Low Latency',
                              'Ultra baja latencia',
                            ),
                            _tr(
                              context,
                              'Prioritize latency over visual stability',
                              'Prioriza la latencia sobre la estabilidad visual',
                            ),
                            c.ultraLowLatency,
                            (v) => settings.updateConfig(
                              c.copyWith(ultraLowLatency: v),
                            ),
                          ),
                          if (c.ultraLowLatency)
                            _toggle(
                              _tr(
                                context,
                                'Low Latency Frame Balance',
                                'Balance de frames en baja latencia',
                              ),
                              _tr(
                                context,
                                'Reduce jitter scheduling frames — only with ultra low latency',
                                'Reduce jitter al programar frames, sólo con ultra baja latencia',
                              ),
                              c.lowLatencyFrameBalance,
                              (v) => settings.updateConfig(
                                c.copyWith(lowLatencyFrameBalance: v),
                              ),
                            ),
                          _toggle(
                            'HDR',
                            l.hdrDesc,
                            c.enableHdr,
                            (v) =>
                                settings.updateConfig(c.copyWith(enableHdr: v)),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Full Range Color',
                              'Color de rango completo',
                            ),
                            _tr(
                              context,
                              'Use 0-255 instead of 16-235',
                              'Usa 0-255 en lugar de 16-235',
                            ),
                            c.fullRange,
                            (v) =>
                                settings.updateConfig(c.copyWith(fullRange: v)),
                          ),

                          _section(_tr(context, 'Audio', 'Audio')),
                          _choiceTile(
                            context,
                            _tr(context, 'Audio', 'Audio'),
                            _audioLabel(context, c.audioConfig),
                            () => _pickAudio(context, settings, c),
                          ),
                          _choiceTile(
                            context,
                            _tr(context, 'Audio Quality', 'Calidad de audio'),
                            c.audioQuality == AudioQuality.high
                                ? _tr(
                                    context,
                                    'High (256 Kbps/ch)',
                                    'Alta (256 Kbps/canal)',
                                  )
                                : _tr(
                                    context,
                                    'Normal (96 Kbps/ch)',
                                    'Normal (96 Kbps/canal)',
                                  ),
                            () => _pickAudioQuality(context, settings, c),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Play Audio on PC',
                              'Reproducir audio en el PC',
                            ),
                            _tr(
                              context,
                              'Keep sound on host PC too',
                              'Mantiene también el sonido en el PC anfitrión',
                            ),
                            c.playLocalAudio,
                            (v) => settings.updateConfig(
                              c.copyWith(playLocalAudio: v),
                            ),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Local Audio Effects',
                              'Efectos locales de audio',
                            ),
                            _tr(
                              context,
                              'Apply light client-side loudness and surround processing',
                              'Aplica un refuerzo ligero y virtualización surround en el cliente',
                            ),
                            c.enableAudioFx,
                            (v) => settings.updateConfig(
                              c.copyWith(enableAudioFx: v),
                            ),
                          ),
                          _buildKofiSection(context),
                        ],
                      ),
                    ),
                  ),
                  FocusScope(
                    node: _tabScopes[2],
                    child: FocusTraversalGroup(
                      policy: OrderedTraversalPolicy(),
                      child: ListView(
                        padding: const EdgeInsets.only(top: 16, bottom: 160),
                        children: [
                          _section(
                            _tr(context, 'Input / Touch', 'Entrada / táctil'),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Show Button Hints',
                              'Mostrar pistas de botones',
                            ),
                            _tr(
                              context,
                              'Display gamepad button icons in the interface',
                              'Muestra iconos del mando en la interfaz',
                            ),
                            preferences.showButtonHints,
                            (v) => preferences.setShowButtonHints(v),
                          ),
                          if (preferences.showButtonHints)
                            _choiceTile(
                              context,
                              _tr(context, 'Button Style', 'Estilo de botones'),
                              preferences.buttonScheme == 'playstation'
                                  ? 'PlayStation'
                                  : 'Xbox',
                              () => _pickButtonScheme(context, preferences),
                            ),
                          _choiceTile(
                            context,
                            _tr(context, 'Touch Mode', 'Modo táctil'),
                            _mouseLabel(context, c.mouseMode),
                            () => _pickMouseMode(context, settings, c),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Mouse Emulation',
                              'Emulación de ratón',
                            ),
                            _tr(
                              context,
                              'Gamepad stick emulates mouse',
                              'El stick del mando emula el ratón',
                            ),
                            c.mouseEmulation,
                            (v) => settings.updateConfig(
                              c.copyWith(mouseEmulation: v),
                            ),
                          ),
                          _toggle(
                            _tr(context, 'Gamepad → Mouse', 'Mando → ratón'),
                            _tr(
                              context,
                              'Use gamepad to move cursor',
                              'Usa el mando para mover el cursor',
                            ),
                            c.gamepadMouseEmulation,
                            (v) => settings.updateConfig(
                              c.copyWith(gamepadMouseEmulation: v),
                            ),
                          ),
                          if (c.gamepadMouseEmulation)
                            _sliderTile(
                              _tr(
                                context,
                                'Gamepad Mouse Speed',
                                'Velocidad del ratón con mando',
                              ),
                              '${c.gamepadMouseSpeed.toStringAsFixed(1)}x',
                              c.gamepadMouseSpeed,
                              0.5,
                              5.0,
                              18,
                              (v) => settings.updateConfig(
                                c.copyWith(gamepadMouseSpeed: v),
                              ),
                              labelBuilder: (v) => '${v.toStringAsFixed(1)}x',
                            ),
                          _toggle(
                            _tr(
                              context,
                              'Local Mouse Cursor',
                              'Cursor local del ratón',
                            ),
                            _tr(
                              context,
                              'Show a local cursor overlay instead of a remote one',
                              'Muestra un cursor local en vez del cursor remoto',
                            ),
                            c.mouseLocalCursor,
                            (v) => settings.updateConfig(
                              c.copyWith(mouseLocalCursor: v),
                            ),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Absolute Mouse Mode',
                              'Modo de ratón absoluto',
                            ),
                            _tr(
                              context,
                              'Direct cursor positioning (pen/stylus) rather than relative drag',
                              'Posicionamiento directo del cursor (lápiz/stylus) en lugar de arrastre relativo',
                            ),
                            c.absoluteMouseMode,
                            (v) => settings.updateConfig(
                              c.copyWith(absoluteMouseMode: v),
                            ),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Multi-Touch Gestures',
                              'Gestos multitáctiles',
                            ),
                            _tr(
                              context,
                              'Map pinch/rotate/swipe to PC equivalents',
                              'Mapea pellizcar, rotar y deslizar a acciones equivalentes del PC',
                            ),
                            c.multiTouchGestures,
                            (v) => settings.updateConfig(
                              c.copyWith(multiTouchGestures: v),
                            ),
                          ),
                          if (c.mouseMode == MouseMode.trackpad) ...[
                            _sliderTile(
                              _tr(
                                context,
                                'Trackpad Sensitivity X',
                                'Sensibilidad X del trackpad',
                              ),
                              '${(c.trackpadSensitivityX / 100).toStringAsFixed(1)}x',
                              c.trackpadSensitivityX.toDouble(),
                              50,
                              400,
                              14,
                              (v) => settings.updateConfig(
                                c.copyWith(trackpadSensitivityX: v.toInt()),
                              ),
                              labelBuilder: (v) => '${(v / 100).toStringAsFixed(1)}x',
                            ),
                            _sliderTile(
                              _tr(
                                context,
                                'Trackpad Sensitivity Y',
                                'Sensibilidad Y del trackpad',
                              ),
                              '${(c.trackpadSensitivityY / 100).toStringAsFixed(1)}x',
                              c.trackpadSensitivityY.toDouble(),
                              50,
                              400,
                              14,
                              (v) => settings.updateConfig(
                                c.copyWith(trackpadSensitivityY: v.toInt()),
                              ),
                              labelBuilder: (v) => '${(v / 100).toStringAsFixed(1)}x',
                            ),
                          ],

                          _section(_tr(context, 'Keyboard', 'Teclado')),
                          _toggle(
                            _tr(
                              context,
                              'Force QWERTY Layout',
                              'Forzar layout QWERTY',
                            ),
                            _tr(
                              context,
                              'Ignore device keyboard locale, always use QWERTY',
                              'Ignora el idioma del teclado del dispositivo y usa siempre QWERTY',
                            ),
                            c.forceQwertyLayout,
                            (v) => settings.updateConfig(
                              c.copyWith(forceQwertyLayout: v),
                            ),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Back Button = Meta (Win key)',
                              'Botón Atrás = Meta (tecla Win)',
                            ),
                            _tr(
                              context,
                              'Send Windows key when Back is pressed',
                              'Envía la tecla Windows al pulsar Atrás',
                            ),
                            c.backButtonAsMeta,
                            (v) => settings.updateConfig(
                              c.copyWith(
                                backButtonAsMeta: v,
                                backButtonAsGuide: v
                                    ? false
                                    : c.backButtonAsGuide,
                              ),
                            ),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Back Button = Guide (Xbox button)',
                              'Botón Atrás = Guide (botón Xbox)',
                            ),
                            _tr(
                              context,
                              'Send Xbox Guide button when Back is pressed',
                              'Envía el botón Guide de Xbox al pulsar Atrás',
                            ),
                            c.backButtonAsGuide,
                            (v) => settings.updateConfig(
                              c.copyWith(
                                backButtonAsGuide: v,
                                backButtonAsMeta: v
                                    ? false
                                    : c.backButtonAsMeta,
                              ),
                            ),
                          ),

                          _section(_tr(context, 'Gamepad', 'Mando')),
                          _toggle(
                            _tr(
                              context,
                              'Flip Face Buttons',
                              'Invertir botones frontales',
                            ),
                            _tr(
                              context,
                              'Swap A/B and X/Y',
                              'Intercambia A/B y X/Y',
                            ),
                            c.flipFaceButtons,
                            (v) => settings.updateConfig(
                              c.copyWith(flipFaceButtons: v),
                            ),
                          ),
                          _toggle(
                            l.multipleControllers,
                            l.multipleControllersDesc,
                            c.multiControllerEnabled,
                            (v) => settings.updateConfig(
                              c.copyWith(multiControllerEnabled: v),
                            ),
                          ),
                          if (c.multiControllerEnabled)
                            _choiceTile(
                              context,
                              _tr(
                                context,
                                'Controller Count',
                                'Cantidad de mandos',
                              ),
                              c.controllerCount == 0
                                  ? 'AUTO'
                                  : _tr(
                                      context,
                                      '${c.controllerCount} controller${c.controllerCount > 1 ? 's' : ''}',
                                      '${c.controllerCount} mando${c.controllerCount > 1 ? 's' : ''}',
                                    ),
                              () => _pickControllerCount(context, settings, c),
                            ),
                          _choiceTile(
                            context,
                            _tr(
                              context,
                              'Controller Driver',
                              'Driver del mando',
                            ),
                            _controllerDriverLabel(context, c.controllerDriver),
                            () => _pickControllerDriver(context, settings, c),
                          ),
                          _sliderTile(
                            _tr(context, 'Deadzone', 'Zona muerta'),
                            '${c.deadzone}%',
                            c.deadzone.toDouble(),
                            -20,
                            20,
                            40,
                            (v) => settings.updateConfig(
                              c.copyWith(deadzone: v.toInt()),
                            ),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Enhanced USB/XInput Detection',
                              'Deteccion USB/XInput mejorada',
                            ),
                            _tr(
                              context,
                              'Allow relaxed matching for generic wired controllers during streaming',
                              'Permite un reconocimiento mas flexible de mandos por cable durante el streaming',
                            ),
                            c.usbDriverEnabled,
                            (v) => settings.updateConfig(
                              c.copyWith(usbDriverEnabled: v),
                            ),
                          ),
                          if (c.usbDriverEnabled)
                            _toggle(
                              _tr(
                                context,
                                'USB Bind All',
                                'Vincular todos los USB',
                              ),
                              _tr(
                                context,
                                'Also admit external HID pads that expose only partial gamepad reports',
                                'Tambien admite pads HID externos que solo exponen reportes parciales de mando',
                              ),
                              c.usbBindAll,
                              (v) => settings.updateConfig(
                                c.copyWith(usbBindAll: v),
                              ),
                            ),
                          _toggle(
                            _tr(context, 'Joy-Con Support', 'Soporte Joy-Con'),
                            _tr(
                              context,
                              'Allow split Nintendo Joy-Con style controllers to register as stream inputs',
                              'Permite que controles estilo Joy-Con divididos se registren como entrada del stream',
                            ),
                            c.joyCon,
                            (v) => settings.updateConfig(c.copyWith(joyCon: v)),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Battery Status Report',
                              'Reporte de batería',
                            ),
                            _tr(
                              context,
                              'Report controller battery level to the host PC',
                              'Envía el nivel de batería del mando al PC anfitrión',
                            ),
                            c.gamepadBatteryReport,
                            (v) => settings.updateConfig(
                              c.copyWith(gamepadBatteryReport: v),
                            ),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Motion Sensors',
                              'Sensores de movimiento',
                            ),
                            _tr(
                              context,
                              'Send gyroscope / accelerometer data (DualSense/Switch)',
                              'Envía datos de giroscopio y acelerómetro (DualSense/Switch)',
                            ),
                            c.gamepadMotionSensors,
                            (v) => settings.updateConfig(
                              c.copyWith(gamepadMotionSensors: v),
                            ),
                          ),
                          if (c.gamepadMotionSensors)
                            _toggle(
                              _tr(
                                context,
                                'Motion Fallback (touchscreen)',
                                'Respaldo de movimiento (pantalla táctil)',
                              ),
                              _tr(
                                context,
                                'Use the device screen as a virtual gyroscope',
                                'Usa la pantalla del dispositivo como giroscopio virtual',
                              ),
                              c.gamepadMotionFallback,
                              (v) => settings.updateConfig(
                                c.copyWith(gamepadMotionFallback: v),
                              ),
                            ),
                          _toggle(
                            _tr(
                              context,
                              'Touchpad as Mouse',
                              'Touchpad como ratón',
                            ),
                            _tr(
                              context,
                              'Use DualShock/DualSense touchpad for cursor control',
                              'Usa el touchpad de DualShock/DualSense para controlar el cursor',
                            ),
                            c.gamepadTouchpadAsMouse,
                            (v) => settings.updateConfig(
                              c.copyWith(gamepadTouchpadAsMouse: v),
                            ),
                          ),
                          _choiceTile(
                            context,
                            _tr(context, 'Button Remap', 'Remapeo de botones'),
                            _buttonRemapLabel(context, c.buttonRemapProfile),
                            () => _pickButtonRemap(context, settings, c),
                          ),
                          ExcludeFocus(
                            excluding: true,
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: 0.38,
                                child: _FocusableNavTile(
                                  icon: Icons.tune_rounded,
                                  title: _tr(
                                    context,
                                    'Controller Layout Editor',
                                    'Editor de layout del mando',
                                  ),
                                  subtitle: _tr(
                                    context,
                                    'Open the visual remap editor',
                                    'Abrir el editor visual de remapeo',
                                  ),
                                  onTap: () {},
                                ),
                              ),
                            ),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Vibration Fallback',
                              'Respaldo de vibración',
                            ),
                            _tr(
                              context,
                              'Vibrate the phone when the controller rumble fires',
                              'Hace vibrar el teléfono cuando se activa el rumble del mando',
                            ),
                            c.vibrateFallback,
                            (v) => settings.updateConfig(
                              c.copyWith(vibrateFallback: v),
                            ),
                          ),
                          if (c.vibrateFallback) ...[
                            _toggle(
                              _tr(
                                context,
                                'Device Rumble',
                                'Vibración del dispositivo',
                              ),
                              _tr(
                                context,
                                'Use full device rumble motor for vibration feedback',
                                'Usa el motor principal del dispositivo para la vibración',
                              ),
                              c.deviceRumble,
                              (v) => settings.updateConfig(
                                c.copyWith(deviceRumble: v),
                              ),
                            ),
                            _sliderTile(
                              _tr(
                                context,
                                'Vibration Strength',
                                'Intensidad de vibración',
                              ),
                              '${c.vibrateFallbackStrength}%',
                              c.vibrateFallbackStrength.toDouble(),
                              0,
                              100,
                              20,
                              (v) => settings.updateConfig(
                                c.copyWith(vibrateFallbackStrength: v.toInt()),
                              ),
                            ),
                          ],

                          _section(
                            _tr(
                              context,
                              'On-Screen Controls',
                              'Controles en pantalla',
                            ),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Show Virtual Gamepad',
                              'Mostrar mando virtual',
                            ),
                            _tr(
                              context,
                              'Display on-screen controller',
                              'Muestra el mando en pantalla',
                            ),
                            c.showOnscreenControls,
                            (v) => settings.updateConfig(
                              c.copyWith(showOnscreenControls: v),
                            ),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Hide with Physical Gamepad',
                              'Ocultar con mando físico',
                            ),
                            _tr(
                              context,
                              'Auto-hide when controller connected',
                              'Se oculta automáticamente al conectar un mando',
                            ),
                            c.hideOscWithGamepad,
                            (v) => settings.updateConfig(
                              c.copyWith(hideOscWithGamepad: v),
                            ),
                          ),
                          _sliderTile(
                            _tr(context, 'Opacity', 'Opacidad'),
                            '${c.oscOpacity}%',
                            c.oscOpacity.toDouble(),
                            0,
                            100,
                            20,
                            (v) => settings.updateConfig(
                              c.copyWith(oscOpacity: v.toInt()),
                            ),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Vibration / Rumble',
                              'Vibración / rumble',
                            ),
                            _tr(
                              context,
                              'Haptic feedback on buttons',
                              'Respuesta háptica en los botones',
                            ),
                            c.enableRumble,
                            (v) => settings.updateConfig(
                              c.copyWith(enableRumble: v),
                            ),
                          ),
                          _buildKofiSection(context),
                        ],
                      ),
                    ),
                  ),
                  FocusScope(
                    node: _tabScopes[3],
                    child: FocusTraversalGroup(
                      policy: OrderedTraversalPolicy(),
                      child: ListView(
                        padding: const EdgeInsets.only(top: 16, bottom: 160),
                        children: [
                          _section(_tr(context, 'Desktop', 'Escritorio')),
                          _toggle(
                            _tr(
                              context,
                              'Allow Fullscreen',
                              'Permitir pantalla completa',
                            ),
                            _tr(
                              context,
                              'App starts in borderless fullscreen mode. Press F11 to toggle.',
                              'La app inicia en modo pantalla completa sin bordes. F11 para alternar.',
                            ),
                            preferences.desktopFullscreen,
                            (v) {
                              preferences.setDesktopFullscreen(v);
                              FullscreenService.setFullscreen(v);
                            },
                          ),
                          _buildKofiSection(context),
                        ],
                      ),
                    ),
                  ),
                  FocusScope(
                    node: _tabScopes[4],
                    child: FocusTraversalGroup(
                      policy: OrderedTraversalPolicy(),
                      child: ListView(
                        padding: const EdgeInsets.only(top: 16, bottom: 160),
                        children: [
                          _section(_tr(context, 'Host', 'Host')),
                          _toggle(
                            _tr(
                              context,
                              'Optimize Game Settings',
                              'Optimizar ajustes del juego',
                            ),
                            _tr(
                              context,
                              'Let server adjust game settings',
                              'Permite que el servidor ajuste la configuración del juego',
                            ),
                            c.enableSops,
                            (v) => settings.updateConfig(
                              c.copyWith(enableSops: v),
                            ),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Picture in Picture (PiP)',
                              'Picture in Picture (PiP)',
                            ),
                            AppLocalizations.of(context).pipDesc,
                            c.pipEnabled,
                            (v) => settings.updateConfig(
                              c.copyWith(pipEnabled: v),
                            ),
                          ),

                          _section(_tr(context, 'Plugins', 'Plugins')),
                          _FocusableNavTile(
                            icon: Icons.extension_outlined,
                            title: _tr(context, 'Plugins', 'Plugins'),
                            subtitle: _tr(
                              context,
                              'Game metadata, background videos…',
                              'Metadatos de juegos, videos de fondo…',
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PluginsScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          _FocusableNavTile(
                            icon: Icons.vpn_lock_rounded,
                            title: l.remoteAccessVpn,
                            subtitle: l.remoteAccessVpnDesc,
                            onTap: () => VpnGuideSheet.show(context),
                          ),

                          _section(_tr(context, 'Collections', 'Colecciones')),
                          _FocusableNavTile(
                            icon: Icons.folder_special_outlined,
                            title: AppLocalizations.of(context).myCollections,
                            subtitle: _tr(
                              context,
                              'Organize your games into custom groups',
                              'Organiza tus juegos en grupos personalizados',
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CollectionsScreen(),
                              ),
                            ),
                          ),

                          _section('Jujo Labs'),
                          // Dynamic Bitrate removed — causes excessive reconnects
                          // that depend on server-side support. Disabled until
                          // in-band bitrate renegotiation is implemented.
                          _toggle(
                            _tr(
                              context,
                              'Session Metrics',
                              'Métricas de sesión',
                            ),
                            _tr(
                              context,
                              'Show a post-session report dialog after closing a stream',
                              'Mostrar un reporte al cerrar una sesión de streaming',
                            ),
                            c.enableSessionMetrics,
                            (v) => settings.updateConfig(
                              c.copyWith(enableSessionMetrics: v),
                            ),
                          ),
                          if (c.enableSessionMetrics)
                            _sliderTile(
                              _tr(context, 'Metrics Auto-Dismiss', 'Auto-cerrar métricas'),
                              c.metricsDismissSec == 0
                                  ? _tr(context, 'Off', 'Desactivado')
                                  : '${c.metricsDismissSec}s',
                              c.metricsDismissSec.toDouble(),
                              0,
                              60,
                              12,
                              (v) => settings.updateConfig(
                                c.copyWith(metricsDismissSec: v.toInt()),
                              ),
                              labelBuilder: (v) => v == 0
                                  ? _tr(context, 'Off', 'Desactivado')
                                  : '${v.toInt()}s',
                            ),

                          _choiceTile(
                            context,
                            _tr(
                              context,
                              'Overlay Trigger',
                              'Trigger del overlay',
                            ),
                            _overlayTriggerLabel(
                              context,
                              c.overlayTriggerCombo,
                              c.overlayTriggerHoldMs,
                            ),
                            () => _showOverlayTriggerDialog(
                              context,
                              settings,
                              c,
                              preferences.buttonScheme,
                            ),
                            leading: const Icon(
                              Icons.gamepad_outlined,
                              color: Colors.white54,
                              size: 18,
                            ),
                          ),

                          // Desktop keyboard combo for overlay (macOS / Windows)
                          _choiceTile(
                            context,
                            _tr(
                              context,
                              'Desktop Overlay Combo',
                              'Combo de overlay (escritorio)',
                            ),
                            c.desktopOverlayKeys.isEmpty
                                ? _tr(context, 'None', 'Ninguno')
                                : '${c.desktopOverlayKeys.join(' + ')} • ${(c.desktopOverlayHoldMs / 1000).toStringAsFixed(1)}s',
                            () => _showDesktopComboDialog(context, settings, c),
                            leading: const Icon(
                              Icons.keyboard_outlined,
                              color: Colors.white54,
                              size: 18,
                            ),
                          ),

                          _choiceTile(
                            context,
                            _tr(
                              context,
                              'Mouse Mode Trigger',
                              'Trigger del modo ratón',
                            ),
                            _overlayTriggerLabel(
                              context,
                              c.mouseModeCombo,
                              c.mouseModeHoldMs,
                            ),
                            () => _showMouseModeComboDialog(
                              context,
                              settings,
                              c,
                              preferences.buttonScheme,
                            ),
                            leading: const Icon(
                              Icons.mouse_outlined,
                              color: Colors.white54,
                              size: 18,
                            ),
                          ),

                          _choiceTile(
                            context,
                            _tr(
                              context,
                              'Quick Favorites Trigger',
                              'Trigger de favoritos rápidos',
                            ),
                            _overlayTriggerLabel(
                              context,
                              c.quickFavCombo,
                              c.quickFavHoldMs,
                            ),
                            () => _showQuickFavComboDialog(
                              context,
                              settings,
                              c,
                              preferences.buttonScheme,
                            ),
                            leading: const Icon(
                              Icons.star_outline_rounded,
                              color: Colors.white54,
                              size: 18,
                            ),
                          ),

                          _toggle(
                            _tr(
                              context,
                              'Choreographer Vsync',
                              'Vsync con Choreographer',
                            ),
                            _tr(
                              context,
                              'Align frame presentation to display refresh (reduces jitter)',
                              'Alinea la presentación de frames con el refresco de pantalla y reduce jitter',
                            ),
                            c.choreographerVsync,
                            (v) => settings.updateConfig(
                              c.copyWith(choreographerVsync: v),
                            ),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Variable Refresh Rate',
                              'Frecuencia de refresco variable',
                            ),
                            _tr(
                              context,
                              'Match display Hz to stream FPS (VRR / LTPO panels)',
                              'Ajusta los Hz de la pantalla al FPS del stream (VRR / paneles LTPO)',
                            ),
                            c.enableVrr,
                            (v) =>
                                settings.updateConfig(c.copyWith(enableVrr: v)),
                          ),
                          _toggle(
                            _tr(context, 'Direct Submit', 'Direct Submit'),
                            _tr(
                              context,
                              'Bypass SurfaceTexture — zero-copy rendering (Android 10+)',
                              'Evita SurfaceTexture para renderizado zero-copy (Android 10+)',
                            ),
                            c.enableDirectSubmit,
                            (v) => settings.updateConfig(
                              c.copyWith(enableDirectSubmit: v),
                            ),
                          ),
                          _toggle(
                            _tr(
                              context,
                              'Force Skia Renderer',
                              'Forzar Skia Renderer',
                            ),
                            _tr(
                              context,
                              'Disable Impeller and use Skia/OpenGL. Fixes black screen on some GPUs (requires restart)',
                              'Desactiva Impeller y usa Skia/OpenGL. Corrige pantalla negra en algunas GPUs (requiere reinicio)',
                            ),
                            c.forceSkiaRenderer,
                            (v) => settings.updateConfig(
                              c.copyWith(forceSkiaRenderer: v),
                            ),
                          ),
                          _sliderTile(
                            _tr(
                              context,
                              'Frame Queue Depth',
                              'Profundidad de cola de frames',
                            ),
                            c.frameQueueDepth == 0
                                ? _tr(context, 'Auto', 'Auto')
                                : _tr(
                                    context,
                                    '${c.frameQueueDepth} frame${c.frameQueueDepth > 1 ? 's' : ''}',
                                    '${c.frameQueueDepth} frame${c.frameQueueDepth > 1 ? 's' : ''}',
                                  ),
                            c.frameQueueDepth.toDouble(),
                            0,
                            5,
                            5,
                            (v) => settings.updateConfig(
                              c.copyWith(frameQueueDepth: v.round()),
                            ),
                            labelBuilder: (v) {
                              final i = v.round();
                              if (i == 0) return _tr(context, 'Auto', 'Auto');
                              return '$i frame${i > 1 ? 's' : ''}';
                            },
                          ),

                          _section(_tr(context, 'About', 'Acerca de')),
                          _FocusableNavTile(
                            icon: Icons.info_outline,
                            title: _tr(
                              context,
                              'About & Credits',
                              'Acerca de y créditos',
                            ),
                            subtitle: _tr(
                              context,
                              'Version, credits, Ko-fi',
                              'Versión, créditos, Ko-fi',
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AboutScreen(),
                              ),
                            ),
                          ),

                          _buildKofiSection(context),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildKofiSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 48, bottom: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _tr(context, 'Keep Jujo alive', 'Mantén a JUJO con vida'),
              style: const TextStyle(
                color: Colors.white54,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Focus(
              autofocus: false,
              onKeyEvent: (_, ev) {
                if (ev is! KeyDownEvent) return KeyEventResult.ignored;
                if (ev.logicalKey == LogicalKeyboardKey.enter ||
                    ev.logicalKey == LogicalKeyboardKey.select ||
                    ev.logicalKey == LogicalKeyboardKey.gameButtonA) {
                  launchUrl(Uri.parse('https://ko-fi.com/jujodev'));
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (ctx) {
                  final focused = Focus.of(ctx).hasFocus;
                  return GestureDetector(
                    onTap: () =>
                        launchUrl(Uri.parse('https://ko-fi.com/jujodev')),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: focused
                            ? [
                                BoxShadow(
                                  color: const Color(
                                    0xFF29abe0,
                                  ).withValues(alpha: 0.6),
                                  blurRadius: 16,
                                  spreadRadius: 4,
                                ),
                              ]
                            : [],
                        border: focused
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          'https://storage.ko-fi.com/cdn/kofi2.png?v=3',
                          height: 40,
                          errorBuilder: (_, _, _) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            color: const Color(0xFF29abe0),
                            child: const Text(
                              'Support me on Ko-fi',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageTile(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    return FocusTraversalGroup(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.language, color: Colors.white54),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                'Language / Idioma',
                style: TextStyle(color: Colors.white),
              ),
            ),
            _langBtn(context, localeProvider, 'en', 'EN'),
            const SizedBox(width: 8),
            _langBtn(context, localeProvider, 'es', 'ES'),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountCard(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final tp = context.watch<ThemeProvider>();
    final accent = tp.accent;
    final surface = tp.surface;

    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.05),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!auth.isSignedIn) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.cloud_sync_outlined,
                        color: accent,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _tr(
                              context,
                              'Account & Cloud Sync',
                              'Cuenta y sincronización en la nube',
                            ),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _tr(
                              context,
                              'Back up settings and sync across devices',
                              'Respalda ajustes y sincronízalos entre dispositivos',
                            ),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                ),
                const SizedBox(height: 16),
                _googleSignInButton(
                  context: context,
                  onTap: () async {
                    if (TvDetector.instance.isTV) {
                      if (!context.mounted) return;
                      DeviceFlowScreen.show(context);
                      return;
                    }

                    final ok = await auth.signIn();
                    if (!ok && context.mounted) {
                      if (auth.deviceFlowAvailable) {
                        DeviceFlowScreen.show(context);
                      }
                    }
                  },
                  accent: accent,
                ),
              ] else ...[
                Row(
                  children: [
                    if (auth.photoUrl != null)
                      CircleAvatar(
                        backgroundImage: NetworkImage(auth.photoUrl!),
                        radius: 14,
                      )
                    else
                      Icon(Icons.account_circle, color: accent, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            auth.displayName ??
                                auth.email ??
                                _tr(
                                  context,
                                  'Google Account',
                                  'Cuenta de Google',
                                ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          if (auth.email != null)
                            Text(
                              auth.email!,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _proSyncButton(
                        context: context,
                        icon: Icons.cloud_upload_outlined,
                        label: _tr(context, 'Backup', 'Respaldo'),
                        onTap: auth.isSyncing ? null : () => auth.pushToCloud(),
                        accent: accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _proSyncButton(
                        context: context,
                        icon: Icons.cloud_download_outlined,
                        label: _tr(context, 'Restore', 'Restaurar'),
                        onTap: auth.isSyncing
                            ? null
                            : () => auth.pullFromCloud(),
                        accent: accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _syncButton(
                        context: context,
                        icon: Icons.logout,
                        label: _tr(context, 'Log Out', 'Cerrar sesión'),
                        onTap: auth.isSyncing ? null : () => auth.signOut(),
                        accent: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
                if (auth.isSyncing)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _proSyncButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required Color accent,
  }) {
    return _syncButton(
      context: context,
      icon: icon,
      label: label,
      onTap: onTap,
      accent: accent,
    );
  }

  Widget _syncButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required Color accent,
  }) {
    return Focus(
      onFocusChange: (focused) {
        if (focused) _scrollToTop(context);
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (onTap != null &&
            (key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.gameButtonA)) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: focused ? accent : accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: focused
                        ? accent.withValues(alpha: 0.30)
                        : Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    color: focused ? Colors.white : Colors.white70,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: focused ? Colors.white : Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _googleSignInButton({
    required BuildContext context,
    required VoidCallback? onTap,
    required Color accent,
  }) {
    return Focus(
      onFocusChange: (focused) {
        if (focused) _scrollToTop(context);
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (onTap != null &&
            (key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.gameButtonA)) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: focused ? accent : accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: focused
                        ? accent.withValues(alpha: 0.30)
                        : Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.login_rounded,
                    color: Colors.white.withValues(alpha: 0.9),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _tr(
                      context,
                      'Sign in with Google',
                      'Iniciar sesión con Google',
                    ),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _langBtn(
    BuildContext context,
    LocaleProvider provider,
    String code,
    String label,
  ) {
    final active = provider.locale.languageCode == code;
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          provider.setByLanguageCode(code);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          final themeAccent = context.read<ThemeProvider>().colors.accent;
          return GestureDetector(
            onTap: () => provider.setByLanguageCode(code),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: active
                    ? themeAccent
                    : focused
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: active
                        ? themeAccent.withValues(alpha: 0.25)
                        : Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: active || focused ? Colors.white : Colors.white54,
                  fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLauncherThemePicker(BuildContext context, ThemeProvider tp) {
    final l = AppLocalizations.of(context);
    final themes = LauncherThemeRegistry.all;
    final plugins = context.read<PluginsProvider>();
    return FocusTraversalGroup(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dashboard_outlined, color: Colors.white38, size: 14),
                const SizedBox(width: 8),
                Text(
                  l.launcherThemeLabel.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l.launcherThemeDesc,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: themes.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) {
                  final theme = themes[i];
                  final active = tp.launcherThemeId == theme.id;
                  final isBigScreen = theme.id == LauncherThemeId.bigScreen;
                  final needsApiSetup =
                      isBigScreen && !plugins.hasApiKey('steam_connect');
                  return _LauncherThemeCard(
                    theme: theme,
                    active: active,
                    autofocus: active,
                    requiresSetup: needsApiSetup,
                    onSelect: () {
                      if (needsApiSetup) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Steam API key required for Big Screen mode. '
                              'Configure it in Plugins \u2192 Steam Connect.',
                            ),
                            duration: Duration(seconds: 4),
                          ),
                        );
                        return;
                      }
                      tp.setLauncherTheme(theme.id);
                      context.read<LauncherPreferences>().switchProfile(
                        theme.id.name,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeSelector(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    return FocusTraversalGroup(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: AppThemeId.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final id = AppThemeId.values[index];
              final colors = AppThemes.presets[id]!;
              final active = themeProvider.themeId == id;
              return _ThemeCard(
                id: id,
                colors: colors,
                active: active,
                autofocus:
                    active &&
                    index == AppThemeId.values.indexOf(themeProvider.themeId),
                onSelect: () => themeProvider.setTheme(id),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 28, 16, 8),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
      ),
    ),
  );

  void _showSmartBitrateDisclaimer(BuildContext context) {
    final isEs = Localizations.localeOf(context).languageCode == 'es';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.read<ThemeProvider>().background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(
              Icons.science_outlined,
              color: Color(0xFFFFA500),
              size: 22,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                isEs ? 'Jujo Labs' : 'Jujo Labs',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          isEs
              ? 'Smart Bitrate aún no es una funcionalidad estable. '
                    'Puede presentar comportamientos inesperados. '
                    'Úsala bajo tu propio criterio.'
              : 'Smart Bitrate is not yet a stable feature. '
                    'It may exhibit unexpected behavior. '
                    'Use at your own discretion.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              isEs ? 'Entendido' : 'Got it',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle(
    String title,
    String sub,
    bool value,
    ValueChanged<bool> onChanged, {
    Widget? leading,
  }) {
    return _FocusableSwitchTile(
      title: title,
      subtitle: sub,
      value: value,
      onChanged: onChanged,
      leading: leading,
    );
  }

  Widget _choiceTile(
    BuildContext context,
    String title,
    String value,
    VoidCallback onTap, {
    Widget? leading,
  }) {
    return _FocusableChoiceTile(
      title: title,
      value: value,
      onTap: onTap,
      leading: leading,
    );
  }

  Widget _sliderTile(
    String title,
    String label,
    double value,
    double min,
    double max,
    int divisions,
    ValueChanged<double> onChanged, {
    String Function(double value)? labelBuilder,
  }) {
    return _SliderTile(
      title: title,
      label: label,
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      onChanged: onChanged,
      labelBuilder: labelBuilder,
    );
  }

  String _artQualityLabel(BuildContext context, String quality) {
    final l = AppLocalizations.of(context);
    switch (quality) {
      case 'medium':
        return l.artQualityMedium;
      case 'low':
        return l.artQualityLow;
      default:
        return l.artQualityHigh;
    }
  }

  void _pickArtQuality(BuildContext ctx, ThemeProvider tp) {
    final l = AppLocalizations.of(ctx);
    _showPicker(ctx, l.artQualityLabel, [
      (l.artQualityHigh, () => tp.setArtQuality('high')),
      (l.artQualityMedium, () => tp.setArtQuality('medium')),
      (l.artQualityLow, () => tp.setArtQuality('low')),
    ]);
  }

  void _pickAmbienceLayout(BuildContext ctx, ThemeProvider tp) {
    _showPicker(ctx, _tr(ctx, 'Ambience Layout', 'Diseño de ambiente'), [
      (_tr(ctx, 'Card', 'Tarjeta'), () => tp.setAmbienceLayout('card')),
      (
        _tr(ctx, 'Circular', 'Circular'),
        () => tp.setAmbienceLayout('circular'),
      ),
    ]);
  }

  void _pickAmbienceEffect(BuildContext ctx, ThemeProvider tp) {
    _showPicker(ctx, _tr(ctx, 'Background Effect', 'Efecto de fondo'), [
      (_tr(ctx, 'Waves', 'Ondas'), () => tp.setAmbienceEffect('waves')),
      (
        _tr(ctx, 'Particles', 'Partículas'),
        () => tp.setAmbienceEffect('particles'),
      ),
      (_tr(ctx, 'None', 'Ninguno'), () => tp.setAmbienceEffect('none')),
    ]);
  }

  void _pickStandbySound(BuildContext ctx, ThemeProvider tp) {
    _showPicker(ctx, _tr(ctx, 'Stand-by sound', 'Sonido de espera'), [
      ('Alone', () => tp.setStandbySound('Alone')),
      ('Lost', () => tp.setStandbySound('Lost')),
      ('Room', () => tp.setStandbySound('Room')),
      ('Stars', () => tp.setStandbySound('Stars')),
    ]);
  }

  void _pickResolution(
    BuildContext ctx,
    SettingsProvider s,
    StreamConfiguration c,
  ) {
    _showResolutionPicker(ctx, s);
  }

  static const _resolutionPresets = <(String, int, int)>[
    ('720p', 1280, 720),
    ('900p', 1600, 900),
    ('1080p', 1920, 1080),
    ('1200p', 1920, 1200),
    ('1440p (2K)', 2560, 1440),
    ('1600p', 2560, 1600),
    ('4K (UHD)', 3840, 2160),
    ('5K', 5120, 2880),
    ('8K', 7680, 4320),
    // Ultrawide
    ('UW 1080p', 2560, 1080),
    ('UW 1440p', 3440, 1440),
    ('UW 1600p', 3840, 1600),
    ('Super UW', 5120, 1440),
    // Portrait / vertical
    ('720×1280', 720, 1280),
    ('1080×1920', 1080, 1920),
    ('1080×2400', 1080, 2400),
    ('1440×2560', 1440, 2560),
    ('1440×3200', 1440, 3200),
    // Retro / low
    ('480p', 854, 480),
    ('576p', 1024, 576),
    ('540p', 960, 540),
    // Steam Deck / handheld
    ('Steam Deck', 1280, 800),
    ('ROG Ally', 1920, 1080),
    ('Legion Go', 2560, 1600),
  ];

  void _showResolutionPicker(BuildContext ctx, SettingsProvider s) {
    final tp = ctx.read<ThemeProvider>();
    final size = MediaQuery.sizeOf(ctx);
    final dialogWidth = size.width > 600 ? 380.0 : size.width - 48;
    showGeneralDialog(
      context: ctx,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(ctx).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 230),
      transitionBuilder: (dCtx, anim, _, child) {
        final scale = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.90, end: 1).animate(scale),
          child: FadeTransition(opacity: fade, child: child),
        );
      },
      pageBuilder: (dCtx, _, _) => _ResolutionPickerDialog(
        dialogWidth: dialogWidth,
        maxHeight: size.height * 0.65,
        surface: tp.surface,
        surfaceVariant: tp.surfaceVariant,
        presets: _SettingsScreenState._resolutionPresets,
        onSelect: (w, h) {
          s.setResolution(w, h);
          Navigator.pop(dCtx);
        },
        onDismiss: () => Navigator.pop(dCtx),
      ),
    );
  }

  void _pickFps(BuildContext ctx, SettingsProvider s, StreamConfiguration c) {
    _showPicker(
      ctx,
      _tr(ctx, 'Frame Rate', 'Frecuencia de cuadros'),
      [30, 60, 90, 120].map((f) => ('$f FPS', () => s.setFps(f))).toList(),
    );
  }

  void _pickCodec(BuildContext ctx, SettingsProvider s, StreamConfiguration c) {
    _showPicker(ctx, _tr(ctx, 'Video Codec', 'Códec de video'), [
      (
        _tr(ctx, 'Auto (best for device)', 'Auto (mejor para el dispositivo)'),
        () => s.setVideoCodec(VideoCodec.auto),
      ),
      (
        _tr(ctx, 'H.264 (best compat)', 'H.264 (mejor compatibilidad)'),
        () => s.setVideoCodec(VideoCodec.h264),
      ),
      (
        _tr(ctx, 'H.265 / HEVC', 'H.265 / HEVC'),
        () => s.setVideoCodec(VideoCodec.h265),
      ),
      (
        _tr(ctx, 'AV1 (newest)', 'AV1 (más nuevo)'),
        () => s.setVideoCodec(VideoCodec.av1),
      ),
    ]);
  }

  void _pickScaleMode(
    BuildContext ctx,
    SettingsProvider s,
    StreamConfiguration c,
  ) {
    _showPicker(ctx, _tr(ctx, 'Scale Mode', 'Modo de escala'), [
      (
        _tr(ctx, 'Fit (letterbox)', 'Ajustar (barras)'),
        () => s.setScaleMode(VideoScaleMode.fit),
      ),
      (
        _tr(ctx, 'Fill (crop)', 'Rellenar (recorte)'),
        () => s.setScaleMode(VideoScaleMode.fill),
      ),
      (
        _tr(ctx, 'Stretch', 'Estirar'),
        () => s.setScaleMode(VideoScaleMode.stretch),
      ),
    ]);
  }

  void _pickFramePacing(
    BuildContext ctx,
    SettingsProvider s,
    StreamConfiguration c,
  ) {
    _showPicker(ctx, _tr(ctx, 'Frame Pacing', 'Sincronización de frames'), [
      (
        _tr(ctx, 'Lowest latency', 'Latencia más baja'),
        () => s.updateConfig(c.copyWith(framePacing: FramePacing.latency)),
      ),
      (
        _tr(ctx, 'Balanced', 'Equilibrado'),
        () => s.updateConfig(c.copyWith(framePacing: FramePacing.balanced)),
      ),
      (
        _tr(ctx, 'Cap FPS', 'Limitar FPS'),
        () => s.updateConfig(c.copyWith(framePacing: FramePacing.capFps)),
      ),
      (
        _tr(ctx, 'Smoothness', 'Suavidad'),
        () => s.updateConfig(c.copyWith(framePacing: FramePacing.smoothness)),
      ),
      (
        _tr(ctx, 'Adaptive', 'Adaptativo'),
        () => s.updateConfig(c.copyWith(framePacing: FramePacing.adaptive)),
      ),
    ]);
  }

  void _pickAudio(BuildContext ctx, SettingsProvider s, StreamConfiguration c) {
    _showPicker(ctx, _tr(ctx, 'Audio', 'Audio'), [
      (
        _tr(ctx, 'Stereo', 'Estéreo'),
        () => s.updateConfig(c.copyWith(audioConfig: AudioConfig.stereo)),
      ),
      (
        _tr(ctx, '5.1 Surround', 'Surround 5.1'),
        () => s.updateConfig(c.copyWith(audioConfig: AudioConfig.surround51)),
      ),
      (
        _tr(ctx, '7.1 Surround', 'Surround 7.1'),
        () => s.updateConfig(c.copyWith(audioConfig: AudioConfig.surround71)),
      ),
    ]);
  }

  void _pickAudioQuality(
    BuildContext ctx,
    SettingsProvider s,
    StreamConfiguration c,
  ) {
    _showPicker(ctx, _tr(ctx, 'Audio Quality', 'Calidad de audio'), [
      (
        _tr(ctx, 'High (256 Kbps/ch)', 'Alta (256 Kbps/canal)'),
        () => s.updateConfig(c.copyWith(audioQuality: AudioQuality.high)),
      ),
      (
        _tr(ctx, 'Normal (96 Kbps/ch)', 'Normal (96 Kbps/canal)'),
        () => s.updateConfig(c.copyWith(audioQuality: AudioQuality.normal)),
      ),
    ]);
  }

  void _pickMouseMode(
    BuildContext ctx,
    SettingsProvider s,
    StreamConfiguration c,
  ) {
    _showPicker(ctx, _tr(ctx, 'Touch Mode', 'Modo táctil'), [
      (
        _tr(ctx, 'Direct Touch', 'Toque directo'),
        () => s.updateConfig(c.copyWith(mouseMode: MouseMode.directTouch)),
      ),
      (
        _tr(ctx, 'Trackpad', 'Trackpad'),
        () => s.updateConfig(c.copyWith(mouseMode: MouseMode.trackpad)),
      ),
      (
        _tr(ctx, 'Mouse Cursor', 'Cursor de ratón'),
        () => s.updateConfig(c.copyWith(mouseMode: MouseMode.mouse)),
      ),
    ]);
  }

  void _pickControllerCount(
    BuildContext ctx,
    SettingsProvider s,
    StreamConfiguration c,
  ) {
    _showPicker(ctx, _tr(ctx, 'Controller Count', 'Cantidad de mandos'), [
      (
        _tr(ctx, 'AUTO (detect)', 'AUTO (detectar)'),
        () => s.updateConfig(c.copyWith(controllerCount: 0)),
      ),
      ...[1, 2, 3, 4].map(
        (n) => (
          _tr(
            ctx,
            '$n controller${n > 1 ? 's' : ''}',
            '$n mando${n > 1 ? 's' : ''}',
          ),
          () => s.updateConfig(c.copyWith(controllerCount: n)),
        ),
      ),
    ]);
  }

  void _pickControllerDriver(
    BuildContext ctx,
    SettingsProvider s,
    StreamConfiguration c,
  ) {
    _showPicker(ctx, _tr(ctx, 'Controller Driver', 'Driver del mando'), [
      (
        _tr(ctx, 'Auto (recommended)', 'Auto (recomendado)'),
        () =>
            s.updateConfig(c.copyWith(controllerDriver: ControllerDriver.auto)),
      ),
      (
        'Xbox 360',
        () => s.updateConfig(
          c.copyWith(controllerDriver: ControllerDriver.xbox360),
        ),
      ),
      (
        'DualShock',
        () => s.updateConfig(
          c.copyWith(controllerDriver: ControllerDriver.dualshock),
        ),
      ),
      (
        'DualSense',
        () => s.updateConfig(
          c.copyWith(controllerDriver: ControllerDriver.dualsense),
        ),
      ),
    ]);
  }

  void _showPicker(
    BuildContext ctx,
    String title,
    List<(String, VoidCallback?)> opts,
  ) {
    final tp = ctx.read<ThemeProvider>();
    final size = MediaQuery.sizeOf(ctx);
    final dialogWidth = size.width > 600 ? 360.0 : size.width - 48;
    showGeneralDialog(
      context: ctx,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(ctx).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 230),
      transitionBuilder: (dCtx, anim, _, child) {
        final scale = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.90, end: 1).animate(scale),
          child: FadeTransition(opacity: fade, child: child),
        );
      },
      pageBuilder: (dCtx, _, _) => Focus(
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.gameButtonB ||
              key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            Navigator.pop(dCtx);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: dialogWidth,
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              constraints: BoxConstraints(maxHeight: size.height * 0.75),
              decoration: BoxDecoration(
                color: tp.surface,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: FocusTraversalGroup(
                  policy: WidgetOrderTraversalPolicy(),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 18),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Divider(height: 1, color: tp.surfaceVariant),
                        ...opts.indexed.map(
                          (t) => _FocusablePickerOption(
                            label: t.$2.$1,
                            autofocus: t.$1 == 0 && t.$2.$2 != null,
                            enabled: t.$2.$2 != null,
                            onTap: t.$2.$2 == null
                                ? null
                                : () {
                                    t.$2.$2!();
                                    Navigator.pop(dCtx);
                                  },
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _resLabel(StreamConfiguration c) {
    if (c.isMatchDisplay) return 'Match display';
    for (final p in _SettingsScreenState._resolutionPresets) {
      if (p.$2 == c.width && p.$3 == c.height) {
        return '${p.$1} (${c.width}×${c.height})';
      }
    }
    return '${c.width}×${c.height}';
  }

  String _codecLabel(BuildContext context, VideoCodec v) =>
      {
        VideoCodec.h264: 'H.264',
        VideoCodec.h265: 'H.265',
        VideoCodec.av1: 'AV1',
        VideoCodec.auto: _tr(context, 'Auto', 'Auto'),
      }[v] ??
      '';

  String _scaleLabel(BuildContext context, VideoScaleMode m) =>
      {
        VideoScaleMode.fit: _tr(context, 'Fit', 'Ajustar'),
        VideoScaleMode.fill: _tr(context, 'Fill', 'Rellenar'),
        VideoScaleMode.stretch: _tr(context, 'Stretch', 'Estirar'),
      }[m] ??
      '';

  String _pacingLabel(BuildContext context, FramePacing p) =>
      {
        FramePacing.latency: _tr(
          context,
          'Lowest latency',
          'Latencia más baja',
        ),
        FramePacing.balanced: _tr(context, 'Balanced', 'Equilibrado'),
        FramePacing.capFps: _tr(context, 'Cap FPS', 'Limitar FPS'),
        FramePacing.smoothness: _tr(context, 'Smoothness', 'Suavidad'),
        FramePacing.adaptive: _tr(context, 'Adaptive', 'Adaptativo'),
      }[p] ??
      '';

  String _audioLabel(BuildContext context, AudioConfig a) =>
      {
        AudioConfig.stereo: _tr(context, 'Stereo', 'Estéreo'),
        AudioConfig.surround51: _tr(context, '5.1', '5.1'),
        AudioConfig.surround71: _tr(context, '7.1', '7.1'),
      }[a] ??
      '';

  String _mouseLabel(BuildContext context, MouseMode m) =>
      {
        MouseMode.directTouch: _tr(context, 'Direct Touch', 'Toque directo'),
        MouseMode.trackpad: _tr(context, 'Trackpad', 'Trackpad'),
        MouseMode.mouse: _tr(context, 'Mouse', 'Ratón'),
      }[m] ??
      '';

  String _controllerDriverLabel(BuildContext context, ControllerDriver d) =>
      {
        ControllerDriver.auto: _tr(context, 'Auto', 'Auto'),
        ControllerDriver.xbox360: 'Xbox 360',
        ControllerDriver.dualshock: 'DualShock',
        ControllerDriver.dualsense: 'DualSense',
      }[d] ??
      '';

  String _buttonRemapLabel(BuildContext context, ButtonRemapProfile p) =>
      {
        ButtonRemapProfile.none: _tr(context, 'Default', 'Predeterminado'),
        ButtonRemapProfile.nintendo: _tr(
          context,
          'Nintendo (swap A/B, X/Y)',
          'Nintendo (intercambia A/B, X/Y)',
        ),
        ButtonRemapProfile.southpaw: _tr(
          context,
          'Southpaw (swap bumpers/sticks)',
          'Southpaw (intercambia bumpers/sticks)',
        ),
        ButtonRemapProfile.custom: _tr(context, 'Custom', 'Personalizado'),
      }[p] ??
      '';

  static const List<MapEntry<String, int>> _overlayButtonDefs = [
    MapEntry('A', 0x1000),
    MapEntry('B', 0x2000),
    MapEntry('X', 0x4000),
    MapEntry('Y', 0x8000),
    MapEntry('LB', 0x0100),
    MapEntry('RB', 0x0200),
    MapEntry('LT', 0x10000),
    MapEntry('RT', 0x20000),
    MapEntry('Start', 0x0010),
    MapEntry('Select', 0x0020),
    MapEntry('Guide', 0x0400),
  ];

  void _pickButtonRemap(
    BuildContext ctx,
    SettingsProvider settings,
    StreamConfiguration c,
  ) {
    _showPicker(
      ctx,
      _tr(ctx, 'Button Remap Profile', 'Perfil de remapeo de botones'),
      [
        (
          _tr(ctx, 'Default', 'Predeterminado'),
          () => settings.updateConfig(
            c.copyWith(buttonRemapProfile: ButtonRemapProfile.none),
          ),
        ),
        (
          _tr(
            ctx,
            'Nintendo (swap A/B, X/Y)',
            'Nintendo (intercambia A/B, X/Y)',
          ),
          () => settings.updateConfig(
            c.copyWith(buttonRemapProfile: ButtonRemapProfile.nintendo),
          ),
        ),
        (
          _tr(
            ctx,
            'Southpaw (swap bumpers/sticks)',
            'Southpaw (intercambia bumpers/sticks)',
          ),
          () => settings.updateConfig(
            c.copyWith(buttonRemapProfile: ButtonRemapProfile.southpaw),
          ),
        ),
        (
          _tr(ctx, 'Custom (edit layout)', 'Personalizado (editar layout)'),
          null,
        ),
      ],
    );
  }

  void _pickButtonScheme(BuildContext ctx, LauncherPreferences preferences) {
    _showPicker(ctx, _tr(ctx, 'Button Style', 'Estilo de botones'), [
      ('Xbox', () => preferences.setButtonScheme('xbox')),
      ('PlayStation', () => preferences.setButtonScheme('playstation')),
    ]);
  }

  String _overlayTriggerLabel(BuildContext context, int combo, int holdMs) {
    if (combo == 0) {
      return _tr(context, 'Disabled', 'Desactivado');
    }
    final names = <String>[];
    for (final entry in _SettingsScreenState._overlayButtonDefs) {
      if ((combo & entry.value) == entry.value) {
        names.add(entry.key);
      }
    }
    final holdLabel = '${(holdMs / 1000).toStringAsFixed(1)}s';
    return '${names.join(' + ')} • $holdLabel';
  }

  void _showOverlayTriggerDialog(
    BuildContext ctx,
    SettingsProvider settings,
    StreamConfiguration config,
    String buttonScheme, {
    String? titleEn,
    String? titleEs,
    String? descEn,
    String? descEs,
  }) {
    final tp = ctx.read<ThemeProvider>();
    final size = MediaQuery.sizeOf(ctx);
    final dialogWidth = size.width > 720 ? 460.0 : size.width - 40;

    showGeneralDialog(
      context: ctx,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(ctx).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 230),
      transitionBuilder: (dCtx, anim, _, child) {
        final scale = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(scale),
          child: FadeTransition(opacity: fade, child: child),
        );
      },
      pageBuilder: (dCtx, _, _) => Focus(
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.gameButtonB ||
              key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            Navigator.pop(dCtx);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: dialogWidth,
              constraints: BoxConstraints(maxHeight: size.height * 0.80),
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              decoration: BoxDecoration(
                color: tp.surface,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: _OverlayTriggerDialog(
                combo: config.overlayTriggerCombo,
                holdMs: config.overlayTriggerHoldMs,
                buttonScheme: buttonScheme,
                titleEn: titleEn,
                titleEs: titleEs,
                descEn: descEn,
                descEs: descEs,
                onChanged: (combo, holdMs) {
                  settings.updateConfig(
                    config.copyWith(
                      overlayTriggerCombo: combo,
                      overlayTriggerHoldMs: holdMs,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Available modifier + function keys for the desktop overlay combo picker.
  static const _desktopKeyOptions = [
    'Shift',
    'Ctrl',
    'Alt',
    'Meta',
    '-',
    'F1',
    'F2',
    'F3',
    'F4',
    'F5',
    'F6',
    'F7',
    'F8',
    'F9',
    'F10',
    'F11',
    'F12',
    'Tab',
    'Space',
    '`',
  ];

  void _showDesktopComboDialog(
    BuildContext ctx,
    SettingsProvider settings,
    StreamConfiguration config,
  ) {
    final tp = ctx.read<ThemeProvider>();
    final size = MediaQuery.sizeOf(ctx);
    final dialogWidth = size.width > 620 ? 440.0 : size.width - 40;
    List<String> selected = List<String>.from(config.desktopOverlayKeys);
    int holdMs = config.desktopOverlayHoldMs;

    showGeneralDialog(
      context: ctx,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(ctx).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx2, anim, _) => StatefulBuilder(
        builder: (ctx2, setDialogState) {
          void toggle(String key) {
            setDialogState(() {
              if (selected.contains(key)) {
                selected.remove(key);
              } else {
                selected.add(key);
              }
            });
          }

          return Center(
            child: Material(
              color: tp.surface,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: dialogWidth,
                constraints: BoxConstraints(maxHeight: size.height * 0.85),
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.keyboard_outlined,
                            color: Colors.white54,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _tr(
                                ctx2,
                                'Desktop Overlay Combo',
                                'Combo de overlay (escritorio)',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _tr(
                          ctx2,
                          'Select the key combination and hold time to open the stream overlay on desktop (macOS / Windows).',
                          'Elige la combinación de teclas y el tiempo de pulsación para abrir el overlay en escritorio (macOS / Windows).',
                        ),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Current selection preview
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            Text(
                              selected.isEmpty
                                  ? _tr(ctx2, 'None', 'Ninguno')
                                  : '${selected.join(' + ')} • ${(holdMs / 1000).toStringAsFixed(1)}s',
                              style: TextStyle(
                                color: selected.isEmpty
                                    ? Colors.white38
                                    : Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Key grid
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _desktopKeyOptions.map((key) {
                          final isOn = selected.contains(key);
                          return GestureDetector(
                            onTap: () => toggle(key),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: isOn
                                    ? tp.accent.withValues(alpha: 0.22)
                                    : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isOn ? tp.accent : Colors.white24,
                                  width: isOn ? 1.5 : 1.0,
                                ),
                              ),
                              child: Text(
                                key,
                                style: TextStyle(
                                  color: isOn ? tp.accentLight : Colors.white70,
                                  fontSize: 13,
                                  fontWeight: isOn
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 18),
                      // Hold time slider
                      Text(
                        _tr(ctx2, 'Hold Time', 'Tiempo de pulsación'),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                activeTrackColor: tp.accent,
                                inactiveTrackColor: Colors.white12,
                                thumbColor: tp.accent,
                                overlayColor: tp.accent.withValues(alpha: 0.12),
                                trackHeight: 3,
                              ),
                              child: Slider(
                                value: holdMs.toDouble(),
                                min: 0,
                                max: 5000,
                                divisions: 50,
                                onChanged: (v) => setDialogState(
                                  () => holdMs = (v / 100).round() * 100,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: Text(
                              '${(holdMs / 1000).toStringAsFixed(1)}s',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: tp.accentLight,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: () {
                              setDialogState(() {
                                selected = ['Shift', '-'];
                                holdMs = 0;
                              });
                            },
                            child: Text(
                              _tr(ctx2, 'Reset to default', 'Restablecer'),
                            ),
                          ),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx2),
                                child: Text(_tr(ctx2, 'Cancel', 'Cancelar')),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: tp.accent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: () {
                                  settings.updateConfig(
                                    config.copyWith(
                                      desktopOverlayKeys: List.from(selected),
                                      desktopOverlayHoldMs: holdMs,
                                    ),
                                  );
                                  Navigator.pop(ctx2);
                                },
                                child: Text(_tr(ctx2, 'Save', 'Guardar')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showMouseModeComboDialog(
    BuildContext ctx,
    SettingsProvider settings,
    StreamConfiguration config,
    String buttonScheme,
  ) {
    final tp = ctx.read<ThemeProvider>();
    final size = MediaQuery.sizeOf(ctx);
    final dialogWidth = size.width > 720 ? 460.0 : size.width - 40;

    showGeneralDialog(
      context: ctx,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(ctx).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      pageBuilder: (dCtx, _, _) => Focus(
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.gameButtonB ||
              key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            Navigator.pop(dCtx);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: dialogWidth,
              constraints: BoxConstraints(maxHeight: size.height * 0.80),
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              decoration: BoxDecoration(
                color: tp.surface,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: _OverlayTriggerDialog(
                combo: config.mouseModeCombo,
                holdMs: config.mouseModeHoldMs,
                buttonScheme: buttonScheme,
                titleEn: 'Mouse Mode Trigger',
                titleEs: 'Trigger del modo ratón',
                descEn: 'Choose the buttons that toggle mouse emulation mode.',
                descEs:
                    'Elige los botones que activan el modo de emulación de ratón.',
                onChanged: (combo, holdMs) {
                  settings.updateConfig(
                    config.copyWith(
                      mouseModeCombo: combo,
                      mouseModeHoldMs: holdMs,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showQuickFavComboDialog(
    BuildContext ctx,
    SettingsProvider settings,
    StreamConfiguration config,
    String buttonScheme,
  ) {
    final tp = ctx.read<ThemeProvider>();
    final size = MediaQuery.sizeOf(ctx);
    final dialogWidth = size.width > 720 ? 460.0 : size.width - 40;

    showGeneralDialog(
      context: ctx,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(ctx).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      pageBuilder: (dCtx, _, _) => Focus(
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.gameButtonB ||
              key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            Navigator.pop(dCtx);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: dialogWidth,
              constraints: BoxConstraints(maxHeight: size.height * 0.80),
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              decoration: BoxDecoration(
                color: tp.surface,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: _OverlayTriggerDialog(
                combo: config.quickFavCombo,
                holdMs: config.quickFavHoldMs,
                buttonScheme: buttonScheme,
                titleEn: 'Quick Favorites Trigger',
                titleEs: 'Trigger de favoritos rápidos',
                descEn:
                    'Choose the buttons that open the quick favorites panel during gameplay.',
                descEs:
                    'Elige los botones que abren el panel de favoritos rápidos durante el juego.',
                onChanged: (combo, holdMs) {
                  settings.updateConfig(
                    config.copyWith(
                      quickFavCombo: combo,
                      quickFavHoldMs: holdMs,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderTile extends StatefulWidget {
  final String title, label;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final String Function(double value)? labelBuilder;
  final FocusNode? focusNode;
  final KeyEventResult Function(FocusNode node, KeyEvent event)?
  onKeyEventOverride;

  const _SliderTile({
    required this.title,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.labelBuilder,
    this.focusNode,
    this.onKeyEventOverride,
  });

  @override
  State<_SliderTile> createState() => _SliderTileState();
}

class _SliderTileState extends State<_SliderTile> {
  late double _v;
  bool _editing = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _v = widget.value;
  }

  @override
  void didUpdateWidget(_SliderTile old) {
    super.didUpdateWidget(old);
    _v = widget.value;
  }

  void _stepBy(int direction) {
    final step = (widget.max - widget.min) / widget.divisions;
    final next = (_v + direction * step).clamp(widget.min, widget.max);
    setState(() => _v = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        final overridden = widget.onKeyEventOverride?.call(node, event);
        if (overridden != null && overridden != KeyEventResult.ignored) {
          return overridden;
        }
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          setState(() => _editing = !_editing);
          return KeyEventResult.handled;
        }

        if (_editing) {
          if (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowRight) {
            _stepBy(key == LogicalKeyboardKey.arrowRight ? 1 : -1);
            return KeyEventResult.handled;
          }

          if (key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack ||
              key == LogicalKeyboardKey.gameButtonB) {
            setState(() => _editing = false);
            return KeyEventResult.handled;
          }
        }

        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _focused && !_editing
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.transparent,
          border: _editing
              ? Border.all(
                  color: context.read<ThemeProvider>().colors.accent,
                  width: 2,
                )
              : _focused
              ? Border.all(
                  color: context.read<ThemeProvider>().colors.accent.withValues(
                    alpha: 0.6,
                  ),
                  width: 1.5,
                )
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          title: Row(
            children: [
              Text(widget.title, style: const TextStyle(color: Colors.white)),
              const Spacer(),
              if (_editing)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.tune,
                    color: context.read<ThemeProvider>().colors.accentLight,
                    size: 16,
                  ),
                ),
              Text(
                _labelFor(_v),
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
          subtitle: ExcludeFocus(
            excluding: !_editing,
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: context.read<ThemeProvider>().colors.accent,
                thumbColor: context.read<ThemeProvider>().colors.accentLight,
                inactiveTrackColor: Colors.white12,
                overlayColor: context
                    .read<ThemeProvider>()
                    .colors
                    .accent
                    .withValues(alpha: 0.15),
              ),
              child: Slider(
                value: _v.clamp(widget.min, widget.max),
                min: widget.min,
                max: widget.max,
                divisions: widget.divisions,
                onChanged: (v) => setState(() => _v = v),
                onChangeEnd: widget.onChanged,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _labelFor(double v) {
    if (widget.labelBuilder != null) {
      return widget.labelBuilder!(v);
    }
    if (widget.max >= 1000) return '${v ~/ 1000} Mbps';
    return '${v.toInt()}%';
  }
}

class _CollapsableSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _CollapsableSection({
    required this.title,
    required this.icon,
    required this.child,
  });
  @override
  State<_CollapsableSection> createState() => _CollapsableSectionState();
}

class _CollapsableSectionState extends State<_CollapsableSection> {
  bool _open = false;
  final FocusNode _headerFocus = FocusNode(debugLabel: 'collapsable-header');

  @override
  void dispose() {
    _headerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Focus(
        focusNode: _headerFocus,
        onFocusChange: (_) => setState(() {}),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;

          if (node.hasPrimaryFocus) {
            if (key == LogicalKeyboardKey.gameButtonA ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.select) {
              setState(() => _open = !_open);
              return KeyEventResult.handled;
            }

            if (_open && key == LogicalKeyboardKey.arrowDown) {
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
            _headerFocus.requestFocus();
            return KeyEventResult.handled;
          }

          if (key == LogicalKeyboardKey.arrowUp) {
            final firstFocusable = node.descendants
                .where((d) => d.canRequestFocus && !d.skipTraversal)
                .firstOrNull;
            final focused = node.descendants
                .where((d) => d.hasPrimaryFocus)
                .firstOrNull;
            if (focused != null && focused == firstFocusable) {
              _headerFocus.requestFocus();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: tp.surface,
            borderRadius: BorderRadius.circular(14),
            border: _headerFocus.hasFocus
                ? Border.all(
                    color: tp.accent.withValues(alpha: 0.5),
                    width: 1.5,
                  )
                : Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => setState(() => _open = !_open),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(widget.icon, color: Colors.white54, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.expand_more,
                          color: Colors.white38,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_open)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    FocusTraversalGroup(
                      policy: WidgetOrderTraversalPolicy(),
                      child: widget.child,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LauncherThemeCard extends StatefulWidget {
  final LauncherTheme theme;
  final bool active;
  final bool autofocus;
  final bool requiresSetup;
  final VoidCallback onSelect;

  const _LauncherThemeCard({
    required this.theme,
    required this.active,
    required this.autofocus,
    required this.onSelect,
    this.requiresSetup = false,
  });

  @override
  State<_LauncherThemeCard> createState() => _LauncherThemeCardState();
}

class _LauncherThemeCardState extends State<_LauncherThemeCard> {
  bool _focused = false;

  IconData _iconFor(LauncherThemeId id) => switch (id) {
    LauncherThemeId.classic => Icons.view_carousel,
    LauncherThemeId.backbone => Icons.dashboard_outlined,
    LauncherThemeId.ps5 => Icons.gamepad_outlined,
    LauncherThemeId.hero => Icons.auto_awesome,
    LauncherThemeId.bigScreen => Icons.tv_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
    final highlighted = widget.active || _focused;
    void select() => widget.onSelect();
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          select();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: select,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 120,
          decoration: BoxDecoration(
            color: highlighted ? tp.accent.withValues(alpha: 0.10) : tp.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _focused
                  ? Colors.white54
                  : widget.active
                  ? tp.accent.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.06),
              width: _focused ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    _iconFor(widget.theme.id),
                    color: highlighted ? tp.accent : Colors.white38,
                    size: 20,
                  ),
                  if (widget.requiresSetup)
                    const Positioned(
                      top: -4,
                      right: -8,
                      child: Icon(
                        Icons.lock_outline,
                        size: 11,
                        color: Colors.amberAccent,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                widget.theme.name(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: highlighted ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight: highlighted ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
              if (widget.active)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: tp.accent,
                      shape: BoxShape.circle,
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

class _ComingSoonThemeCard extends StatefulWidget {
  final String label;
  final IconData icon;
  const _ComingSoonThemeCard({required this.label, required this.icon});

  @override
  State<_ComingSoonThemeCard> createState() => _ComingSoonThemeCardState();
}

class _ComingSoonThemeCardState extends State<_ComingSoonThemeCard> {
  bool _focused = false;

  void _showComingSoon() {
    ComingSoonDialog.show(context, featureName: '${widget.label} Theme');
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          _showComingSoon();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _showComingSoon,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 120,
          decoration: BoxDecoration(
            color: _focused ? Colors.white.withValues(alpha: 0.08) : tp.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _focused ? Colors.white54 : Colors.white12,
              width: _focused ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    widget.icon,
                    color: _focused ? Colors.white54 : Colors.white24,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _focused ? Colors.white54 : Colors.white30,
                  fontSize: 11,
                  fontWeight: _focused ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeCard extends StatefulWidget {
  final AppThemeId id;
  final AppThemeColors colors;
  final bool active;
  final bool autofocus;
  final VoidCallback onSelect;

  const _ThemeCard({
    required this.id,
    required this.colors,
    required this.active,
    required this.autofocus,
    required this.onSelect,
  });

  @override
  State<_ThemeCard> createState() => _ThemeCardState();
}

class _ThemeCardState extends State<_ThemeCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final highlighted = widget.active || _focused;
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          widget.onSelect();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 90,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                c.background,
                Color.lerp(c.surface, c.accent, highlighted ? 0.18 : 0.07)!,
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _focused
                  ? Colors.white54
                  : widget.active
                  ? c.accent.withValues(alpha: 0.5)
                  : c.accent.withValues(alpha: 0.1),
              width: highlighted ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: highlighted ? 0.25 : 0.12),
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      AppThemes.icon(widget.id),
                      color: highlighted
                          ? c.accent
                          : c.accentLight.withValues(alpha: 0.7),
                      size: 15,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _dot(c.accent),
                  const SizedBox(width: 3),
                  _dot(c.accentLight),
                  const SizedBox(width: 3),
                  _dot(c.highlight),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                AppThemes.label(widget.id),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: highlighted ? Colors.white : Colors.white60,
                  fontSize: 10,
                  fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _FocusableSwitchTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? leading;

  const _FocusableSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.leading,
  });

  @override
  State<_FocusableSwitchTile> createState() => _FocusableSwitchTileState();
}

class _FocusableSwitchTileState extends State<_FocusableSwitchTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          widget.onChanged(!widget.value);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _focused
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.transparent,
          border: Border.all(
            color: _focused
                ? context.read<ThemeProvider>().colors.accentLight.withValues(
                    alpha: 0.3,
                  )
                : Colors.transparent,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: widget.leading != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    widget.leading!,
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.title,
                        style: const TextStyle(color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              : Text(widget.title, style: const TextStyle(color: Colors.white)),
          subtitle: Text(
            widget.subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          value: widget.value,
          activeThumbColor: context.read<ThemeProvider>().colors.accent,
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}

class _FocusableChoiceTile extends StatefulWidget {
  final String title;
  final String value;
  final VoidCallback onTap;
  final Widget? leading;

  const _FocusableChoiceTile({
    required this.title,
    required this.value,
    required this.onTap,
    this.leading,
  });

  @override
  State<_FocusableChoiceTile> createState() => _FocusableChoiceTileState();
}

class _FocusableChoiceTileState extends State<_FocusableChoiceTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _focused
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.transparent,
          border: Border.all(
            color: _focused
                ? context.read<ThemeProvider>().colors.accentLight.withValues(
                    alpha: 0.3,
                  )
                : Colors.transparent,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: widget.leading != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    widget.leading!,
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.title,
                        style: const TextStyle(color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              : Text(widget.title, style: const TextStyle(color: Colors.white)),
          subtitle: Text(
            widget.value,
            style: const TextStyle(color: Colors.white54),
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: _focused ? Colors.white : Colors.white38,
          ),
          onTap: widget.onTap,
        ),
      ),
    );
  }
}

class _FocusablePickerOption extends StatefulWidget {
  final String label;
  final bool autofocus;
  final bool enabled;
  final VoidCallback? onTap;

  const _FocusablePickerOption({
    required this.label,
    this.autofocus = false,
    this.enabled = true,
    this.onTap,
  });

  @override
  State<_FocusablePickerOption> createState() => _FocusablePickerOptionState();
}

class _FocusablePickerOptionState extends State<_FocusablePickerOption> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // Disabled options: no focus, no tap, visually dimmed with "coming soon" badge
    if (!widget.enabled) {
      return Opacity(
        opacity: 0.38,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Soon',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: _focused
              ? Colors.white.withValues(alpha: 0.09)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Text(
            widget.label,
            style: TextStyle(
              color: _focused ? Colors.white : Colors.white70,
              fontWeight: _focused ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusableNavTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FocusableNavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_FocusableNavTile> createState() => _FocusableNavTileState();
}

class _FocusableNavTileState extends State<_FocusableNavTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _focused
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.transparent,
          border: _focused
              ? Border.all(
                  color: context.read<ThemeProvider>().colors.accent.withValues(
                    alpha: 0.6,
                  ),
                  width: 1.5,
                )
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          leading: Icon(
            widget.icon,
            color: _focused
                ? Colors.white
                : context.read<ThemeProvider>().colors.accentLight,
          ),
          title: Text(
            widget.title,
            style: const TextStyle(color: Colors.white),
          ),
          subtitle: Text(
            widget.subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: _focused ? Colors.white : Colors.white38,
          ),
          onTap: widget.onTap,
        ),
      ),
    );
  }
}

class _OverlayTriggerDialog extends StatefulWidget {
  final int combo;
  final int holdMs;
  final String buttonScheme;
  final void Function(int combo, int holdMs) onChanged;
  final String? titleEn;
  final String? titleEs;
  final String? descEn;
  final String? descEs;

  const _OverlayTriggerDialog({
    required this.combo,
    required this.holdMs,
    required this.buttonScheme,
    required this.onChanged,
    this.titleEn,
    this.titleEs,
    this.descEn,
    this.descEs,
  });

  @override
  State<_OverlayTriggerDialog> createState() => _OverlayTriggerDialogState();
}

class _OverlayTriggerDialogState extends State<_OverlayTriggerDialog> {
  late int _combo;
  late int _holdMs;
  late final FocusNode _holdFocusNode;
  late final FocusNode _recordFocusNode;

  // Record mode state
  bool _recording = false;
  bool _recordBtnFocused = false;
  final Set<int> _pressedNow = {};
  final Set<int> _pressedSession = {};

  // Physical gamepad key → moonlight bitmask (no L/R stick — not available as LogicalKeyboardKey)
  static final Map<LogicalKeyboardKey, int> _hwToFlag = {
    LogicalKeyboardKey.gameButtonA: 0x1000,
    LogicalKeyboardKey.gameButtonB: 0x2000,
    LogicalKeyboardKey.gameButtonX: 0x4000,
    LogicalKeyboardKey.gameButtonY: 0x8000,
    LogicalKeyboardKey.gameButtonLeft1: 0x0100,
    LogicalKeyboardKey.gameButtonRight1: 0x0200,
    LogicalKeyboardKey.gameButtonLeft2: 0x10000,
    LogicalKeyboardKey.gameButtonRight2: 0x20000,
    LogicalKeyboardKey.gameButtonStart: 0x0010,
    LogicalKeyboardKey.gameButtonSelect: 0x0020,
    LogicalKeyboardKey.gameButtonMode: 0x0400,
  };

  @override
  void initState() {
    super.initState();
    _combo = widget.combo;
    _holdMs = widget.holdMs;
    _holdFocusNode = FocusNode(debugLabel: 'overlay-hold');
    _holdFocusNode.addListener(() {
      if (!_holdFocusNode.hasFocus || !mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _holdFocusNode.context;
        if (ctx != null && mounted) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.85,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    });
    _recordFocusNode = FocusNode(debugLabel: 'overlay-record');
    _recordFocusNode.addListener(() {
      if (!_recordFocusNode.hasFocus || !mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _recordFocusNode.context;
        if (ctx != null && mounted) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    if (_recording) HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _holdFocusNode.dispose();
    _recordFocusNode.dispose();
    super.dispose();
  }

  void _startRecording() {
    setState(() {
      _recording = true;
      _pressedNow.clear();
      _pressedSession.clear();
    });
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  void _stopRecording() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    if (_pressedSession.isNotEmpty) {
      final newCombo = _pressedSession.fold(0, (acc, f) => acc | f);
      setState(() => _combo = newCombo);
      widget.onChanged(newCombo, _holdMs);
    }
    setState(() {
      _recording = false;
      _pressedNow.clear();
      _pressedSession.clear();
    });
    // Return focus to Record button so user can record again
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recordFocusNode.requestFocus();
    });
  }

  bool _onHardwareKey(KeyEvent event) {
    if (!_recording) return false;
    final flag = _hwToFlag[event.logicalKey];
    if (flag == null) return false;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      setState(() {
        _pressedNow.add(flag);
        _pressedSession.add(flag);
      });
    } else if (event is KeyUpEvent) {
      setState(() => _pressedNow.remove(flag));
      if (_pressedNow.isEmpty && _pressedSession.isNotEmpty) {
        _stopRecording();
      }
    }
    return true;
  }

  // Button positions as fractions of controller visual (x, y)
  Widget _buildButtonGrid(AppThemeColors tp) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _SettingsScreenState._overlayButtonDefs.map((entry) {
        final isSelected = (_combo & entry.value) == entry.value;
        final isLive = _pressedNow.contains(entry.value);
        final highlighted = isSelected || isLive;
        final asset = GamepadButtonHelper.instance.assetFor(switch (entry.key) {
          'Guide' => 'HOME',
          'Select' => 'SELECT',
          'Start' => 'START',
          _ => entry.key,
        }, scheme: widget.buttonScheme);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: isLive
                ? tp.accent.withValues(alpha: 0.30)
                : isSelected
                ? tp.accent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.06),
            border: Border.all(
              color: isLive
                  ? tp.accent
                  : isSelected
                  ? tp.accent.withValues(alpha: 0.70)
                  : Colors.white.withValues(alpha: 0.15),
              width: highlighted ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                asset,
                width: 18,
                height: 18,
                filterQuality: FilterQuality.medium,
              ),
              const SizedBox(width: 5),
              Text(
                entry.key,
                style: TextStyle(
                  color: highlighted ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _tr(context, 'Hold', 'Mantener');
    final theme = context.read<ThemeProvider>().colors;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── title + record button ─────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _tr(
                              context,
                              widget.titleEn ?? 'Overlay Trigger',
                              widget.titleEs ?? 'Trigger del overlay',
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _tr(
                              context,
                              widget.descEn ??
                                  'Choose the buttons that open the in-game overlay.',
                              widget.descEs ??
                                  'Elige los botones que abren el overlay en juego.',
                            ),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // ── Record button (focusable via gamepad) ──────
                    Focus(
                      focusNode: _recordFocusNode,
                      autofocus: true,
                      onFocusChange: (f) =>
                          setState(() => _recordBtnFocused = f),
                      onKeyEvent: (_, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
                        final k = event.logicalKey;
                        if (k == LogicalKeyboardKey.enter ||
                            k == LogicalKeyboardKey.select ||
                            k == LogicalKeyboardKey.gameButtonA) {
                          _recording ? _stopRecording() : _startRecording();
                          return KeyEventResult.handled;
                        }
                        if (k == LogicalKeyboardKey.arrowDown) {
                          _holdFocusNode.requestFocus();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: _recording
                              ? const Color(0xFFFF4081).withValues(alpha: 0.18)
                              : theme.accent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _recordBtnFocused
                                ? Colors.white54
                                : _recording
                                ? const Color(0xFFFF4081).withValues(alpha: 0.7)
                                : theme.accent.withValues(alpha: 0.5),
                            width: _recordBtnFocused ? 1.5 : 1.0,
                          ),
                        ),
                        child: InkWell(
                          onTap: _recording ? _stopRecording : _startRecording,
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _recording
                                      ? Icons.stop_rounded
                                      : Icons.fiber_manual_record_rounded,
                                  size: 14,
                                  color: _recording
                                      ? const Color(0xFFFF4081)
                                      : Colors.white70,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _recording
                                      ? _tr(context, 'Stop', 'Parar')
                                      : _tr(context, 'Record', 'Grabar'),
                                  style: TextStyle(
                                    color: _recording
                                        ? const Color(0xFFFF4081)
                                        : Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ), // AnimatedContainer
                    ), // Focus
                  ],
                ),
                const SizedBox(height: 12),
                // ── recording status / preview ─────────────────────
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _recording
                        ? const Color(0xFFFF4081).withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _recording
                          ? const Color(0xFFFF4081).withValues(alpha: 0.35)
                          : Colors.white10,
                    ),
                  ),
                  child: Text(
                    _recording
                        ? (_pressedSession.isEmpty
                              ? _tr(
                                  context,
                                  'Press gamepad buttons…',
                                  'Presiona botones del mando…',
                                )
                              : _SettingsScreenState._overlayButtonDefs
                                    .where(
                                      (e) => _pressedSession.contains(e.value),
                                    )
                                    .map((e) => e.key)
                                    .join(' + '))
                        : (_combo == 0
                              ? _tr(context, 'Disabled', 'Desactivado')
                              : '$summary ${_SettingsScreenState._overlayButtonDefs.where((entry) => (_combo & entry.value) == entry.value).map((entry) => entry.key).join(' + ')} • ${(_holdMs / 1000).toStringAsFixed(1)}s'),
                    style: TextStyle(
                      color: _recording
                          ? (_pressedSession.isEmpty
                                ? const Color(0xFFFF4081)
                                : Colors.white)
                          : (_combo == 0 ? Colors.white38 : Colors.white),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_recording) ...[
                  const SizedBox(height: 6),
                  Text(
                    _tr(
                      context,
                      'Hold the combination, then release all buttons to confirm.',
                      'Mantén la combinación y suelta todos los botones para confirmar.',
                    ),
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
                const SizedBox(height: 14),
                // ── button grid ──────────────────────────────────
                _buildButtonGrid(theme),
                const SizedBox(height: 18),
                // ── hold time ─────────────────────────────────────
                _SliderTile(
                  title: _tr(context, 'Hold Time', 'Tiempo de pulsacion'),
                  label: '',
                  value: _holdMs.toDouble(),
                  min: 0,
                  max: 5000,
                  divisions: 50,
                  focusNode: _holdFocusNode,
                  labelBuilder: (value) =>
                      '${(value / 1000).toStringAsFixed(1)}s',
                  onKeyEventOverride: (node, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _recordFocusNode.requestFocus();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  onChanged: (value) {
                    setState(() => _holdMs = value.round());
                    widget.onChanged(_combo, _holdMs);
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  _tr(
                    context,
                    'Press Record, then hold buttons on the gamepad. Release all to save the combo.',
                    'Presiona Grabar, luego manten los botones en el mando. Suelta todos para guardar.',
                  ),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomResolutionTile extends StatefulWidget {
  final int currentWidth;
  final int currentHeight;
  final int matchDisplayWidth;
  final int matchDisplayHeight;
  final void Function(int width, int height) onApply;

  const _CustomResolutionTile({
    required this.currentWidth,
    required this.currentHeight,
    required this.matchDisplayWidth,
    required this.matchDisplayHeight,
    required this.onApply,
  });

  @override
  State<_CustomResolutionTile> createState() => _CustomResolutionTileState();
}

class _CustomResolutionTileState extends State<_CustomResolutionTile> {
  late final TextEditingController _wCtrl;
  late final TextEditingController _hCtrl;
  final FocusNode _wFocus = FocusNode();
  final FocusNode _hFocus = FocusNode();
  bool _focused = false;
  // Editing mode: when false, TextFields are excluded from focus traversal
  // so the D-pad cannot land on them directly. Only A-press activates them.
  bool _editing = false;

  bool _isPreset(int w, int h) {
    if (w == widget.matchDisplayWidth && h == widget.matchDisplayHeight) {
      return true;
    }
    for (final p in _SettingsScreenState._resolutionPresets) {
      if (p.$2 == w && p.$3 == h) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    final preset = _isPreset(widget.currentWidth, widget.currentHeight);
    _wCtrl = TextEditingController(
      text: preset ? '' : widget.currentWidth.toString(),
    );
    _hCtrl = TextEditingController(
      text: preset ? '' : widget.currentHeight.toString(),
    );

    // B / Escape while a TextField is focused → exit editing mode and
    // return focus to the outer tile. KeyEventResult.handled prevents
    // the B press from propagating up and popping the settings screen.
    for (final fn in [_wFocus, _hFocus]) {
      fn.onKeyEvent = (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final k = event.logicalKey;
        if (k == LogicalKeyboardKey.gameButtonB ||
            k == LogicalKeyboardKey.escape ||
            k == LogicalKeyboardKey.goBack) {
          node.unfocus();
          setState(() => _editing = false);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      };
    }
  }

  @override
  void didUpdateWidget(covariant _CustomResolutionTile old) {
    super.didUpdateWidget(old);
    if (old.currentWidth != widget.currentWidth ||
        old.currentHeight != widget.currentHeight) {
      if (_isPreset(widget.currentWidth, widget.currentHeight)) {
        _wCtrl.clear();
        _hCtrl.clear();
      } else {
        _wCtrl.text = widget.currentWidth.toString();
        _hCtrl.text = widget.currentHeight.toString();
      }
    }
  }

  @override
  void dispose() {
    _wCtrl.dispose();
    _hCtrl.dispose();
    _wFocus.dispose();
    _hFocus.dispose();
    super.dispose();
  }

  void _tryApply() {
    final w = int.tryParse(_wCtrl.text.trim());
    final h = int.tryParse(_hCtrl.text.trim());
    if (w == null || h == null) return;
    if (w < 320 || w > 7680 || h < 240 || h > 4320) return;
    if (w == widget.currentWidth && h == widget.currentHeight) return;
    widget.onApply(w, h);
  }

  @override
  Widget build(BuildContext context) {
    final isEs = AppLocalizations.of(context).locale.languageCode == 'es';
    final accent = context.read<ThemeProvider>().colors.accentLight;
    final hasCustom = _wCtrl.text.isNotEmpty && _hCtrl.text.isNotEmpty;

    return Focus(
      onFocusChange: (f) {
        setState(() {
          _focused = f;
          // When the tile loses focus entirely, exit editing mode so the
          // fields are excluded from traversal again next time.
          if (!f) _editing = false;
        });
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          setState(() => _editing = true);
          // Defer focus until ExcludeFocus rebuilds with excluding: false,
          // then explicitly show the soft keyboard.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _wFocus.requestFocus();
            SystemChannels.textInput.invokeMethod('TextInput.show');
          });
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _focused
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.transparent,
          border: Border.all(
            color: _focused
                ? accent.withValues(alpha: 0.3)
                : Colors.transparent,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEs ? 'Resolucion personalizada' : 'Custom Resolution',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasCustom
                          ? (isEs
                                ? 'Sobreescribe el preset seleccionado'
                                : 'Overrides the selected preset')
                          : (isEs
                                ? 'Vacio = usa el preset de arriba'
                                : 'Empty = uses preset above'),
                      style: TextStyle(
                        color: hasCustom
                            ? accent.withValues(alpha: 0.8)
                            : Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() => _editing = true);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _wFocus.requestFocus();
                    SystemChannels.textInput.invokeMethod('TextInput.show');
                  });
                },
                child: ExcludeFocus(
                  excluding: !_editing,
                  child: IgnorePointer(
                    ignoring: !_editing,
                    child: _buildField(
                      _wCtrl,
                      _wFocus,
                      isEs ? 'Ancho' : 'Width',
                      accent,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  'x',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() => _editing = true);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _hFocus.requestFocus();
                    SystemChannels.textInput.invokeMethod('TextInput.show');
                  });
                },
                child: ExcludeFocus(
                  excluding: !_editing,
                  child: IgnorePointer(
                    ignoring: !_editing,
                    child: _buildField(
                      _hCtrl,
                      _hFocus,
                      isEs ? 'Alto' : 'Height',
                      accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController ctrl,
    FocusNode focusNode,
    String hint,
    Color accent,
  ) {
    return SizedBox(
      width: 72,
      height: 34,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: focusNode.hasFocus
                ? accent.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.1),
            width: focusNode.hasFocus ? 1.5 : 1,
          ),
          color: focusNode.hasFocus
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.03),
        ),
        child: TextField(
          controller: ctrl,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.2),
              fontSize: 12,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 8,
            ),
            isDense: true,
          ),
          onChanged: (_) {
            setState(() {});
            _tryApply();
          },
          onSubmitted: (_) {
            _tryApply();
            if (focusNode == _wFocus) _hFocus.requestFocus();
          },
        ),
      ),
    );
  }
}

class _ResolutionPickerDialog extends StatefulWidget {
  final double dialogWidth;
  final double maxHeight;
  final Color surface;
  final Color surfaceVariant;
  final List<(String, int, int)> presets;
  final void Function(int w, int h) onSelect;
  final VoidCallback onDismiss;

  const _ResolutionPickerDialog({
    required this.dialogWidth,
    required this.maxHeight,
    required this.surface,
    required this.surfaceVariant,
    required this.presets,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  State<_ResolutionPickerDialog> createState() =>
      _ResolutionPickerDialogState();
}

class _ResolutionPickerDialogState extends State<_ResolutionPickerDialog> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  List<(String, int, int)> get _filtered {
    if (_query.isEmpty) return widget.presets;
    final q = _query.toLowerCase();
    return widget.presets.where((p) {
      final label = '${p.$1} ${p.$2}x${p.$3}'.toLowerCase();
      return label.contains(q);
    }).toList();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEs = AppLocalizations.of(context).locale.languageCode == 'es';
    final filtered = _filtered;

    return Focus(
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.gameButtonB ||
            key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack) {
          widget.onDismiss();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: widget.dialogWidth,
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
            decoration: BoxDecoration(
              color: widget.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      isEs ? 'Resolucion' : 'Resolution',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: isEs
                              ? 'Buscar resolucion...'
                              : 'Search resolution...',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 13,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: Colors.white.withValues(alpha: 0.3),
                            size: 18,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 0,
                          ),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _query = v.trim()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Divider(height: 1, color: widget.surfaceVariant),
                  Flexible(
                    child: FocusTraversalGroup(
                      policy: WidgetOrderTraversalPolicy(),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: filtered.length + 1,
                        itemBuilder: (ctx, i) {
                          if (i == 0) {
                            final mq = MediaQuery.of(ctx);
                            final dpr = mq.devicePixelRatio;
                            final physW = (mq.size.width * dpr).round();
                            final physH = (mq.size.height * dpr).round();
                            final lbl = isEs
                                ? 'Pantalla  (${physW}x$physH)'
                                : 'Match Display  (${physW}x$physH)';
                            return _FocusablePickerOption(
                              label: lbl,
                              autofocus: true,
                              enabled: true,
                              onTap: () => widget.onSelect(physW, physH),
                            );
                          }
                          final p = filtered[i - 1];
                          return _FocusablePickerOption(
                            label: '${p.$1}  (${p.$2}x${p.$3})',
                            autofocus: false,
                            enabled: true,
                            onTap: () => widget.onSelect(p.$2, p.$3),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Scheme-aware shoulder hint used in the Settings tab bar.
class _TabHintChip extends StatelessWidget {
  final String label;

  const _TabHintChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return GamepadHintIcon(label, size: 28, forceVisible: true);
  }
}
