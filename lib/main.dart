import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'l10n/app_localizations.dart';
import 'providers/auth_provider.dart';
import 'providers/computer_provider.dart';
import 'providers/app_list_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/plugins_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/theme_provider.dart';
import 'services/audio/ui_sound_service.dart';
import 'services/companion/companion_server.dart';
import 'services/crypto/client_identity.dart';
import 'services/preferences/launcher_preferences.dart';
import 'services/database/app_override_service.dart';
import 'services/input/gamepad_button_helper.dart';
import 'services/tv/tv_detector.dart';
import 'screens/pc_view/focus_mode_screen.dart';
import 'screens/pc_view/pc_view_screen.dart';
import 'widgets/tour_overlay.dart';
import 'services/notifications/notification_service.dart';
import 'services/pro/pro_service.dart';
import 'services/crash/crash_service.dart';

class _AppHttpOverrides extends io.HttpOverrides {
  @override
  io.HttpClient createHttpClient(io.SecurityContext? context) {
    final client = super.createHttpClient(ClientIdentity.buildSecurityContext());
    client.badCertificateCallback = (cert, host, port) => true;
    client.maxConnectionsPerHost = 4;
    return client;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;

  if (kDebugMode) {
    debugRepaintRainbowEnabled = false;
    debugPaintSizeEnabled = false;
    debugPaintBaselinesEnabled = false;
    debugPaintLayerBordersEnabled = false;
    debugPaintPointersEnabled = false;
  }
  io.HttpOverrides.global = _AppHttpOverrides();

  // Generate per-device identity (cert + key + uniqueId) on first launch.
  // Must complete before any HTTPS networking starts.
  await ClientIdentity.init();

  unawaited(NotificationService.init());
  unawaited(UiSoundService.ensureInitialized());
  unawaited(ProService().initialize());
  unawaited(CrashService.initialize());

  await TvDetector.instance.init();
  GamepadButtonHelper.instance.init();

  final settingsProvider = SettingsProvider();
  await settingsProvider.loadSettings();

  final localeProvider = await LocaleProvider.load();
  await AppOverrideService.instance.load();
  final pluginsProvider = await PluginsProvider.load();
  final themeProvider = await ThemeProvider.load();

  final launcherPreferences = LauncherPreferences();
  await launcherPreferences.load(themeProvider.launcherThemeId.name);

  final authProvider = AuthProvider();
  unawaited(authProvider.trySilentSignIn());

  if (TvDetector.instance.isTV) {
    unawaited(
      CompanionServer.instance.start(
        pluginsProvider,
        settingsProvider: settingsProvider,
        localeProvider: localeProvider,
        themeProvider: themeProvider,
        launcherPreferences: launcherPreferences,
      ),
    );
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ComputerProvider()),
        ChangeNotifierProvider(create: (_) => AppListProvider(pluginsProvider)),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: launcherPreferences),
        ChangeNotifierProvider.value(value: localeProvider),
        ChangeNotifierProvider.value(value: pluginsProvider),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => ProService()),
      ],
      child: const JujostreamApp(),
    ),
  );
}

class JujostreamApp extends StatelessWidget {
  const JujostreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      title: 'JUJO Stream',
      debugShowCheckedModeBanner: false,
      locale: localeProvider.locale,
      supportedLocales: const [Locale('en'), Locale('es')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: themeProvider.buildThemeData(),
      home: const TourOverlay(child: _FirstRunGate()),
    );
  }
}

class _FirstRunGate extends StatefulWidget {
  const _FirstRunGate();
  @override
  State<_FirstRunGate> createState() => _FirstRunGateState();
}

class _FirstRunGateState extends State<_FirstRunGate>
    with WidgetsBindingObserver {
  static const _prefKey = 'first_run_shown';
  bool _checked = false;
  bool _shouldShow = false;
  bool _showStartupVideo = false;
  String? _startupVideoPath;
  bool _focusModeEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool(_prefKey) ?? false;
    final startupEnabled =
        prefs.getBool('plugin_enabled_startup_intro_video') ?? false;
    final startupPath = prefs.getString(
      PluginsProvider.settingPref('startup_intro_video', 'video_path'),
    );
    final startupPathExists =
        startupPath != null &&
        startupPath.isNotEmpty &&
        await io.File(startupPath).exists();
    final videoTrigger =
        prefs.getString(
          PluginsProvider.settingPref('startup_intro_video', 'video_trigger'),
        ) ??
        'before_app';
    final focusMode = prefs.getBool('focus_mode_enabled') ?? false;
    if (!mounted) return;
    setState(() {
      _checked = true;
      _shouldShow = !shown;
      _showStartupVideo =
          startupEnabled && startupPathExists && videoTrigger == 'before_app';
      _startupVideoPath = startupPath;
      _focusModeEnabled = focusMode;
    });
    if (_shouldShow) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showDisclaimer());
    }
  }

  Future<void> _showDisclaimer() async {
    final l = AppLocalizations.of(context);
    final isEs = l.locale.languageCode == 'es';
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Focus(
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.gameButtonB ||
              key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            SharedPreferences.getInstance().then(
              (p) => p.setBool(_prefKey, true),
            );
            Navigator.pop(ctx);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.select) {
            SharedPreferences.getInstance().then(
              (p) => p.setBool(_prefKey, true),
            );
            Navigator.pop(ctx);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AlertDialog(
          backgroundColor: ctx.read<ThemeProvider>().colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: ctx.read<ThemeProvider>().colors.accentLight,
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                isEs ? 'Bienvenido a JUJO.Stream' : 'Welcome to JUJO.Stream',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Text(
            isEs
                ? 'Para la mejor experiencia, se recomienda usar JUJO.Stream junto con '
                      'Vibepollo + Playnite o Sunshine + PlayniteWatcher.\n\n'
                      'Si no usas Vibepollo, puedes agregar tus juegos manualmente '
                      'desde las apps del servidor (Sunshine/Apollo).\n\n'
                      'Activa los plugins de Metadatos y Videos en la sección de Plugins '
                      'para enriquecer tu biblioteca automáticamente.'
                : 'For the best experience, it is recommended to use JUJO.Stream together with '
                      'Vibepollo + Playnite or Sunshine + PlayniteWatcher.\n\n'
                      'If you don\'t use Vibepollo, you can add your games manually '
                      'from the server apps (Sunshine/Apollo).\n\n'
                      'Enable the Metadata and Video plugins in the Plugins section '
                      'to automatically enrich your library.',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(_prefKey, true);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(
                isEs ? 'Entendido' : 'Got it',
                style: TextStyle(
                  color: ctx.read<ThemeProvider>().colors.accentLight,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    PcViewScreen.pendingTour.value = true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return Scaffold(
        backgroundColor: context.read<ThemeProvider>().background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final Widget base = _focusModeEnabled
        ? const FocusModeScreen()
        : const PcViewScreen();
    if (!_showStartupVideo || _startupVideoPath == null) {
      return base;
    }
    return _StartupVideoOverlay(
      videoPath: _startupVideoPath!,
      child: base,
      onDismissed: () {
        if (!mounted) return;
        setState(() {
          _showStartupVideo = false;
        });
      },
    );
  }
}

class _StartupVideoOverlay extends StatefulWidget {
  final String videoPath;
  final Widget child;
  final VoidCallback onDismissed;

  const _StartupVideoOverlay({
    required this.videoPath,
    required this.child,
    required this.onDismissed,
  });

  @override
  State<_StartupVideoOverlay> createState() => _StartupVideoOverlayState();
}

class _StartupVideoOverlayState extends State<_StartupVideoOverlay> {
  VideoPlayerController? _controller;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final controller = VideoPlayerController.file(io.File(widget.videoPath));
    try {
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      await controller.setLooping(false);
      await controller.play();
      controller.addListener(() {
        if (!mounted) return;
        final value = controller.value;
        if (value.isInitialized &&
            value.duration > Duration.zero &&
            value.position >= value.duration) {
          _dismiss();
        }
      });
      setState(() => _controller = controller);
    } catch (_) {
      controller.dispose();
      _dismiss();
    }
  }

  void _dismiss() {
    if (!_visible) return;
    _visible = false;
    _controller?.dispose();
    _controller = null;
    widget.onDismissed();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_visible)
          GestureDetector(
            onTap: _dismiss,
            child: Container(
              color: Colors.black,
              child: controller != null && controller.value.isInitialized
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: controller.value.size.width,
                            height: controller.value.size.height,
                            child: VideoPlayer(controller),
                          ),
                        ),
                        Positioned(
                          right: 14,
                          bottom: 14,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.black54,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _dismiss,
                            icon: const Icon(Icons.skip_next),
                            label: const Text('Saltar'),
                          ),
                        ),
                      ],
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}
