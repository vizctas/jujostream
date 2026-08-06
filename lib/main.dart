import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n/app_localizations.dart';
import 'providers/auth_provider.dart';
import 'providers/cloud_mfa_provider.dart';
import 'services/auth/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth/cloud_auth_screen.dart';
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
import 'services/startup/startup_animation_preferences.dart';
import 'services/startup/startup_animation_registry.dart';
import 'services/database/app_override_service.dart';
import 'services/input/gamepad_button_helper.dart';
import 'services/input/gamepad_navigation_service.dart';
import 'services/window/fullscreen_service.dart';
import 'platform_channels/gamepad_channel.dart';
import 'services/tv/tv_detector.dart';
import 'screens/pc_view/focus_mode_screen.dart';
import 'screens/pc_view/pc_view_screen.dart';
import 'widgets/tour_overlay.dart';
import 'services/notifications/notification_service.dart';
import 'services/notifications/notification_mirror_controller.dart';
import 'services/notifications/notification_mirror_discovery_service.dart';
import 'services/notifications/notification_mirror_platform.dart';
import 'services/pro/pro_service.dart';
import 'services/crash/crash_service.dart';
import 'services/telemetry/beta_telemetry_service.dart';
import 'ui/motion_policy.dart';

/// Why cloud sign-in is unavailable, if it is. Reported to telemetry at boot.
String? supabaseInitError;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (SupabaseConfig.current.isConfigured) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.current.url,
        publishableKey: SupabaseConfig.current.publishableKey,
      );
    } catch (e) {
      debugPrint('Error initializing Supabase: $e');
      supabaseInitError = e.toString();
    }
  } else {
    // Silent until now: a build made without --dart-define fails every cloud
    // login with "Cloud sync is not configured" and no clue why.
    supabaseInitError =
        'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY missing from this build.';
  }

  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;

  if (kDebugMode) {
    debugRepaintRainbowEnabled = false;
    debugPaintSizeEnabled = false;
    debugPaintBaselinesEnabled = false;
    debugPaintLayerBordersEnabled = false;
    debugPaintPointersEnabled = false;
  }
  await BetaTelemetryService.initialize();
  // Also in release: without this the telemetry log has no NvHttpClient /
  // PairingService / CloudSyncService lines, which is exactly what is needed to
  // diagnose a customer's pairing or "server offline" report.
  BetaTelemetryService.installDebugPrintCapture();
  BetaTelemetryService.event('app_boot', {
    'platform': io.Platform.operatingSystem,
    'debug': kDebugMode,
    'cloudConfigured': SupabaseConfig.current.isConfigured,
    if (supabaseInitError != null) 'cloudInitError': supabaseInitError,
  });

  // Generate per-device identity (cert + key + uniqueId) on first launch.
  // Must complete before any HTTPS networking starts.
  await ClientIdentity.init();

  unawaited(NotificationService.init());
  unawaited(UiSoundService.ensureInitialized());
  unawaited(ProService().initialize());
  await CrashService.initialize();
  BetaTelemetryService.installGlobalHandlers();

  await TvDetector.instance.init();
  GamepadButtonHelper.instance.init();
  if (io.Platform.isWindows) {
    GamepadChannel.init(); // wire MethodCallHandler before first frame
    GamepadNavigationService.init(); // map onNavInput → Flutter focus traversal
  }

  final settingsProvider = SettingsProvider();
  await settingsProvider.loadSettings();

  final localeProvider = await LocaleProvider.load();
  await AppOverrideService.instance.load();
  final pluginsProvider = await PluginsProvider.load();
  final themeProvider = await ThemeProvider.load();

  final launcherPreferences = LauncherPreferences();
  await launcherPreferences.load(themeProvider.launcherThemeId.name);
  final startupAnimationPreferences = await StartupAnimationPreferences.load();

  if (io.Platform.isWindows) {
    FullscreenService.init(initialState: launcherPreferences.desktopFullscreen);
    FullscreenService.onF11Toggle = (bool newState) {
      launcherPreferences.setDesktopFullscreen(newState);
    };
  }

  final authProvider = AuthProvider();
  unawaited(authProvider.trySilentSignIn());

  final notificationMirrorController = NotificationMirrorController.instance;
  await notificationMirrorController.load();
  notificationMirrorController.attachPlatform(
    NotificationMirrorPlatform.instance,
  );

  final computerProvider = ComputerProvider();

  if (TvDetector.instance.isTV ||
      notificationMirrorController.mode != NotificationMirrorMode.off) {
    unawaited(
      CompanionServer.instance.start(
        pluginsProvider,
        settingsProvider: settingsProvider,
        localeProvider: localeProvider,
        themeProvider: themeProvider,
        launcherPreferences: launcherPreferences,
        computerProvider: computerProvider,
        notificationMirror: notificationMirrorController,
      ),
    );
  }
  unawaited(
    NotificationMirrorDiscoveryService.instance.updateAdvertising(
      notificationMirrorController,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: computerProvider),
        ChangeNotifierProvider(create: (_) => AppListProvider(pluginsProvider)),
        ChangeNotifierProvider(create: (_) => CloudMfaProvider()),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: launcherPreferences),
        ChangeNotifierProvider.value(value: startupAnimationPreferences),
        ChangeNotifierProvider.value(value: localeProvider),
        ChangeNotifierProvider.value(value: pluginsProvider),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: notificationMirrorController),
        ChangeNotifierProvider(create: (_) => ProService()),
      ],
      child: const JujostreamApp(),
    ),
  );
  BetaTelemetryService.event('run_app');
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
      builder: (context, child) {
        // Two problems solved in one place.
        //
        // 1. Nothing anywhere respected the system font size, and several
        //    launcher themes put text inside fixed-height bars (72/46/100 px).
        //    An unbounded scale spills that text over the content beneath it,
        //    so the total is clamped to a range those bars can absorb.
        // 2. TvDetector exposes a fontScale for 10-foot viewing, but
        //    tvFontSize()/tvSpacing() had no callers at all and the app has
        //    ~500 hardcoded font sizes. Boosting here reaches all of them at
        //    once instead of editing every call site.
        final systemScale = MediaQuery.textScalerOf(context).scale(1);
        final tvBoost = TvDetector.instance.isTV ? 1.25 : 1.0;
        final effective = (systemScale * tvBoost).clamp(0.85, 1.4);
        return MediaQuery.withClampedTextScaling(
          minScaleFactor: effective,
          maxScaleFactor: effective,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const TourOverlay(child: StartupGate()),
      routes: {'/auth': (context) => const CloudAuthScreen()},
    );
  }
}

class StartupGate extends StatefulWidget {
  const StartupGate({super.key, this.launcherBuilder});

  final Widget Function(bool focusModeEnabled)? launcherBuilder;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate>
    with WidgetsBindingObserver {
  bool _checked = false;
  bool _showStartupAnimation = false;
  bool _focusModeEnabled = false;
  String _startupAnimationId = StartupAnimationRegistry.cinematicV1Id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (SupabaseConfig.current.isConfigured) {
        context.read<CloudMfaProvider>().refresh();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshFocusMode());
    }
  }

  Future<void> _check() async {
    final selected = context.read<StartupAnimationPreferences>().selected;
    final prefs = await SharedPreferences.getInstance();
    final focusMode = prefs.getBool('focus_mode_enabled') ?? true;
    if (!mounted) return;
    setState(() {
      _checked = true;
      _focusModeEnabled = focusMode;
      _startupAnimationId = selected.id;
      _showStartupAnimation = selected.buildsScreen;
    });
  }

  void _onStartupAnimationComplete() {
    if (!mounted) return;
    setState(() => _showStartupAnimation = false);
  }

  Future<void> _refreshFocusMode() async {
    final prefs = await SharedPreferences.getInstance();
    final focusMode = prefs.getBool('focus_mode_enabled') ?? true;
    if (!mounted || focusMode == _focusModeEnabled) return;
    setState(() => _focusModeEnabled = focusMode);
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_showStartupAnimation) {
      final motion = MotionPolicy.fromContext(
        context,
        context.watch<ThemeProvider>(),
      );
      final definition = StartupAnimationRegistry.resolve(_startupAnimationId);
      final builder = definition.builder;
      if (builder != null) {
        return builder(
          onComplete: _onStartupAnimationComplete,
          reducedMotion: motion.reduceMotion,
        );
      }
    }

    final launcherBuilder = widget.launcherBuilder;
    if (launcherBuilder != null) {
      return launcherBuilder(_focusModeEnabled);
    }

    return _focusModeEnabled ? const FocusModeScreen() : const PcViewScreen();
  }
}
