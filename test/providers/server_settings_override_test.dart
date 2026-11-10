import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jujostream/models/stream_configuration.dart';
import 'package:jujostream/providers/settings_provider.dart';
import 'package:jujostream/providers/theme_provider.dart';
import 'package:jujostream/services/preferences/game_preferences_store.dart';
import 'package:jujostream/services/preferences/launcher_preferences.dart';
import 'package:jujostream/themes/launcher_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Global vs Per-Server Options & Overrides', () {
    test(
      'Servers inherit global configuration by default and can override independently',
      () async {
        final settings = SettingsProvider();
        await settings.loadSettings();

        // Set global bitrate to 25 Mbps and FPS to 60
        await settings.setBitrate(25000);
        await settings.setFps(60);

        expect(settings.globalConfig.bitrate, 25000);
        expect(settings.configForServer('server-1').bitrate, 25000);
        expect(settings.configForServer('server-2').bitrate, 25000);
        expect(settings.hasServerOverride('server-1'), isFalse);

        // Switch scope to server-1 and customize bitrate & FPS
        await settings.setScope('server-1', serverName: 'Living Room PC');
        await settings.setBitrate(65000);
        await settings.setFps(120);

        // Server 1 has custom override; Global and Server 2 remain at 25 Mbps / 60 FPS
        expect(settings.hasServerOverride('server-1'), isTrue);
        expect(settings.configForServer('server-1').bitrate, 65000);
        expect(settings.configForServer('server-1').fps, 120);
        expect(settings.globalConfig.bitrate, 25000);
        expect(settings.globalConfig.fps, 60);
        expect(settings.configForServer('server-2').bitrate, 25000);
        expect(settings.configForServer('server-2').fps, 60);

        // Reload from SharedPreferences to verify persistence
        final reloaded = SettingsProvider();
        await reloaded.loadSettings();
        expect(reloaded.hasServerOverride('server-1'), isTrue);
        expect(reloaded.configForServer('server-1').bitrate, 65000);
        expect(reloaded.configForServer('server-1').fps, 120);
        expect(reloaded.configForServer('server-2').bitrate, 25000);
      },
    );

    test(
      'Resetting server override restores inheritance from Global without affecting other servers',
      () async {
        final settings = SettingsProvider();
        await settings.loadSettings();
        await settings.setBitrate(30000);

        await settings.setScope('srv-a', serverName: 'Server A');
        await settings.setBitrate(80000);

        await settings.setScope('srv-b', serverName: 'Server B');
        await settings.setBitrate(15000);

        expect(settings.configForServer('srv-a').bitrate, 80000);
        expect(settings.configForServer('srv-b').bitrate, 15000);

        // Reset srv-a back to Global
        await settings.resetServerToGlobal('srv-a');
        expect(settings.hasServerOverride('srv-a'), isFalse);
        expect(settings.configForServer('srv-a').bitrate, 30000);
        // srv-b override remains intact
        expect(settings.hasServerOverride('srv-b'), isTrue);
        expect(settings.configForServer('srv-b').bitrate, 15000);
      },
    );

    test(
      'LauncherPreferences and ThemeProvider isolate per-server overrides and fallback to global',
      () async {
        final settings = SettingsProvider();
        await settings.loadSettings();
        final themeProvider = await ThemeProvider.load();
        final launcherPrefs = LauncherPreferences();
        await launcherPrefs.load(themeProvider.launcherThemeId.name);

        // Global card width = 180
        launcherPrefs.setCardWidth(180);
        expect(launcherPrefs.cardWidth, 180);

        // Scope to server-x and enable override
        await settings.setScope(
          'server-x',
          serverName: 'Cloud Rig',
          launcherPreferences: launcherPrefs,
          themeProvider: themeProvider,
        );
        await settings.setServerOverrideEnabled(
          'server-x',
          true,
          serverName: 'Cloud Rig',
          launcherPreferences: launcherPrefs,
          themeProvider: themeProvider,
        );

        // Untouched launcher keys inherit global value (180)
        expect(launcherPrefs.cardWidth, 180);

        // Customize card width and launcher theme on server-x
        await themeProvider.setLauncherTheme(LauncherThemeId.ps5);
        launcherPrefs.setCardWidth(220);
        expect(launcherPrefs.cardWidth, 220);
        expect(themeProvider.launcherThemeId, LauncherThemeId.ps5);
        expect(themeProvider.globalLauncherThemeId, LauncherThemeId.classic);

        // Switch back to Global scope: Global still has cardWidth 180 & classic theme
        await settings.setScope(
          null,
          launcherPreferences: launcherPrefs,
          themeProvider: themeProvider,
        );
        expect(themeProvider.launcherThemeId, LauncherThemeId.classic);
        expect(launcherPrefs.cardWidth, 180);
      },
    );

    test(
      '3-tier hierarchy: Global -> Server Override -> Per-Game Profile preserves server optimizations',
      () async {
        final settings = SettingsProvider();
        await settings.loadSettings();
        final gameStore = GamePreferencesStore();

        // Tier 1: Global (20 Mbps, 60 FPS, H.264)
        await settings.updateConfig(
          settings.globalConfig.copyWith(
            bitrate: 20000,
            fps: 60,
            videoCodec: VideoCodec.h264,
            smartBitrateEnabled: true,
            smartBitrateMin: 10000,
            smartBitrateMax: 35000,
          ),
        );

        // Tier 2: Server Override for 'lan-pc' (50 Mbps, 120 FPS, HEVC, Smart Bitrate 25-80 Mbps)
        await settings.setScope('lan-pc', serverName: 'LAN Beast');
        await settings.updateConfig(
          settings.config.copyWith(
            bitrate: 50000,
            fps: 120,
            videoCodec: VideoCodec.h265,
            smartBitrateEnabled: true,
            smartBitrateMin: 25000,
            smartBitrateMax: 80000,
          ),
        );

        // Tier 3: Per-Game Override on 'lan-pc' for app 42 (only overrides HDR = true)
        await gameStore.saveProfile(
          'lan-pc',
          const GamePreferencesProfile(appId: 42, enableHdr: true),
        );

        final serverBase = settings.configForServer('lan-pc');
        final gameProfile = await gameStore.loadProfile('lan-pc', 42);
        final effective = gameProfile.resolve(serverBase);

        expect(effective.bitrate, 50000);
        expect(effective.fps, 120);
        expect(effective.videoCodec, VideoCodec.h265);
        expect(effective.smartBitrateEnabled, isTrue);
        expect(effective.smartBitrateMin, 25000);
        expect(effective.smartBitrateMax, 80000);
        expect(effective.enableHdr, isTrue);
      },
    );
  });
}

