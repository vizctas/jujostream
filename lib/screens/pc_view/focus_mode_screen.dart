import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../models/computer_details.dart';
import '../../providers/computer_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/audio/ui_sound_service.dart';
import '../../services/navigation/async_single_flight.dart';
import '../../services/input/gamepad_button_helper.dart';
import '../../services/tv/tv_detector.dart';
import '../../widgets/computer_options_dialog.dart';
import '../../widgets/focus_music_mini_player.dart';
import '../../widgets/notification_mirror_overlay.dart';
import '../../widgets/now_playing_banner.dart';
import '../../widgets/pairing_dialog.dart';
import '../app_view/app_view_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/profile_screen.dart';
import '../../ui/motion_policy.dart';
import '../about/about_screen.dart';
import 'pc_view_screen.dart';
import 'cloud_badge.dart';
import 'focusable_icon_button.dart';
import 'server_health_loop.dart';
import 'server_profile_images.dart';
import 'server_tile_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cloud_mfa_provider.dart';
import '../../widgets/mfa_bypassed_confirmation_dialog.dart';
import '../../widgets/computer_entry_overlay.dart';
import '../auth/cloud_auth_screen.dart';
import '../../widgets/jujo_brand_title.dart';

/// Preference key for Focus Mode toggle.
const _kFocusModeEnabled = 'focus_mode_enabled';

/// Reads the persisted Focus Mode preference.
Future<bool> isFocusModeEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kFocusModeEnabled) ?? false;
}

/// Writes the Focus Mode preference.
Future<void> setFocusModeEnabled(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kFocusModeEnabled, value);
}

/// Decode ceilings for the per-server artwork.
///
/// Cards top out at 420 logical px wide and circles at 220, so decoding a
/// gallery photo at native resolution — which is what happened before — held
/// tens of megabytes per page in the image cache for nothing.
const int kFocusCardImageCacheWidth = 900;
const int kFocusCircleImageCacheWidth = 480;

String _focusDefaultAsset(int index) =>
    'assets/images/focus/default_focus00${index % 4}.jpg';

class FocusModeScreen extends StatefulWidget {
  const FocusModeScreen({super.key});

  @override
  State<FocusModeScreen> createState() => _FocusModeScreenState();
}

class _FocusModeScreenState extends State<FocusModeScreen>
    with WidgetsBindingObserver {
  final PageController _pageController = PageController(viewportFraction: 0.82);
  int _currentPage = 0;
  bool _autoConnectAttempted = false;
  final AsyncSingleFlight _computerEntryFlight = AsyncSingleFlight();

  final _appBarFocusNodes = List.generate(
    4,
    (i) => FocusNode(debugLabel: 'focus-appbar-icon-$i'),
  );
  final FocusNode _pageViewFocusNode = FocusNode(debugLabel: 'focus-pageview');

  /// Whether keyboard/gamepad focus is on the carousel rather than the app bar.
  /// Drives the selected card's glow so only one thing looks focused at a time.
  bool _pageViewHasFocus = true;

  int _activeAppBarIndex = 0;

  /// True when FocusModeScreen owns the ambient audio — false while a
  /// full-screen route (Settings, AppViewScreen) is pushed on top.  Keeps
  /// the lifecycle-resume handler from restarting music while we are in
  /// a child screen, while still allowing restarts after dialogs/pickers.
  bool _ambientEnabled = true;

  /// Per-server custom background image paths (uuid → path).
  final Map<String, String> _bgPaths = {};

  ServerHealthLoop? _healthLoop;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!TvDetector.instance.isTV) {
      SystemChrome.setPreferredOrientations([]);
    }
    if (io.Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    UiSoundService.playAmbience();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Re-apply after first frame to survive race with previous route's dispose
      if (io.Platform.isAndroid) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
      // Second delayed re-apply: when navigating from PcViewScreen the
      // previous route's dispose can still reset the system bars after our
      // first call above.  A 250ms delay comfortably outlasts the route
      // transition animation and forces the notification bar away.
      if (io.Platform.isAndroid) {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) {
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          }
        });
      }
      final provider = context.read<ComputerProvider>();
      // Immediately poll existing computers to update their status
      for (final computer in provider.computers) {
        provider.pollComputer(computer);
      }
      _loadBgPaths();
      _scheduleAutoConnect();
      _startHealthLoop();
    });
  }

  Future<void> _loadBgPaths() async {
    final stored = await ServerProfileImages.loadAll();
    if (!mounted) return;
    setState(
      () => _bgPaths
        ..clear()
        ..addAll(stored),
    );
  }

  void _scheduleAutoConnect() {
    if (_autoConnectAttempted) return;
    _autoConnectAttempted = true;
    _tryAutoConnect(0);
  }

  void _tryAutoConnect(int attempt) {
    if (!mounted || attempt >= 12) return;
    final provider = context.read<ComputerProvider>();
    final uuid = provider.primaryServerUuid;
    if (uuid == null) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _tryAutoConnect(attempt + 1);
      });
      return;
    }
    final server = provider.primaryServer;
    if (server != null && server.isReachable && server.isPaired) {
      _onComputerTapped(server);
      return;
    }
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _tryAutoConnect(attempt + 1);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Do NOT reset SystemUiMode here — next route (PcViewScreen) owns its own
    // UI mode and Flutter initializes it before disposing this one; resetting
    // here races with the next initState and re-exposes the notification bar.
    UiSoundService.stopAmbience();
    _healthLoop?.stop();
    _pageController.dispose();
    _pageViewFocusNode.dispose();
    for (final node in _appBarFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      UiSoundService.stopAmbience();
    } else if (state == AppLifecycleState.resumed) {
      // Re-apply fullscreen on resume — Android may restore the notification bar
      // after returning from system dialogs, file pickers, or app switcher.
      if (io.Platform.isAndroid) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
      // Use _ambientEnabled (not isCurrent) so the restart fires even when a
      // dialog or image picker is sitting on top of this route.  _ambientEnabled
      // is cleared to false only when a full-screen route is pushed, so it
      // correctly suppresses playback while in Settings or AppViewScreen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_ambientEnabled) return;
        UiSoundService.playAmbience();
      });
    }
  }

  Future<void> _onComputerTapped(ComputerDetails computer) async {
    await _computerEntryFlight.run(() => _performComputerEntry(computer));
  }

  Future<void> _performComputerEntry(ComputerDetails computer) async {
    // See pc_view_screen: `unknown` means "not polled yet", not "down".
    var state = computer.state;
    if (state == ComputerState.unknown) {
      state = await context.read<ComputerProvider>().pollComputer(computer);
      if (!mounted) return;
    }
    if (state == ComputerState.offline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).serverOffline)),
      );
      return;
    }
    OverlayEntry? progress = showComputerEntryOverlay(
      context,
      computerName: computer.name,
    );
    void hideProgress() {
      progress?.remove();
      progress = null;
    }

    try {
      if (!computer.isPaired) {
        final provider = context.read<ComputerProvider>();
        final ok = await provider.verifyPairing(computer);
        if (!mounted) return;
        if (!ok) {
          final mfa = context.read<CloudMfaProvider>();
          final hasSession = hasCloudSession();
          if (computer.isCloud &&
              hasSession &&
              (mfa.status == CloudMfaStatus.setupRequired ||
                  mfa.status == CloudMfaStatus.verifyRequired)) {
            final action = await MfaBypassedConfirmationDialog.show(context);
            if (!mounted) return;
            if (action == MfaBypassedAction.enterMfa) {
              hideProgress();
              final verified = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => const CloudAuthScreen(
                    isFirstRun: false,
                    popOnSuccess: true,
                  ),
                ),
              );
              if (!mounted) return;
              if (verified == true) {
                await _performComputerEntry(computer);
              }
              return;
            } else if (action == MfaBypassedAction.usePin) {
              hideProgress();
              final paired = await showPairingDialog(context, computer);
              if (!mounted || !paired) return;
            }
            return;
          }

          hideProgress();
          final paired = await showPairingDialog(context, computer);
          if (!mounted || !paired) return;
          return;
        }
      } else {
        // ── Entry gate: verify pairing is still valid on the server ─────
        final provider = context.read<ComputerProvider>();
        final stillPaired = await provider.verifyPairing(computer);
        if (!mounted) return;
        if (!stillPaired) {
          final l = AppLocalizations.of(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l.serverUnpaired)));
          return;
        }
      }

      if (!mounted) return;
      hideProgress();

      // Play server enter sound + strong haptic, then stop ambience
      UiSoundService.playServerEnter();
      HapticFeedback.heavyImpact();
      _ambientEnabled = false;
      UiSoundService.stopAmbience();

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AppViewScreen(computer: computer)),
      );

      // Resume ambience when returning — force a clean restart so any
      // lifecycle-driven stopAmbience() that fired during the session
      // does not leave the player silenced.
      if (mounted) {
        _ambientEnabled = true;
        UiSoundService.restartAmbience();
      }

      if (mounted && !TvDetector.instance.isTV) {
        SystemChrome.setPreferredOrientations([]);
      }
    } finally {
      hideProgress();
    }
  }

  /// Cache for [_sortedForDisplay], keyed by the identity of the source list
  /// plus the ranks that drive the ordering.
  List<ComputerDetails>? _sortedCache;
  String? _sortedCacheKey;

  /// Online + paired first, then online + unpaired, then offline.
  ///
  /// This ran as a copy-and-sort on every `Consumer` rebuild — several times a
  /// second while polling. The order only changes when a server's reachability
  /// or pairing does, so key the cache on exactly that.
  List<ComputerDetails> _sortedForDisplay(List<ComputerDetails> source) {
    int rank(ComputerDetails c) {
      if (c.isReachable && c.isPaired) return 0;
      if (c.isReachable) return 1;
      return 2;
    }

    final key = source.map((c) => '${c.uuid}:${rank(c)}').join('|');
    final cached = _sortedCache;
    if (cached != null && key == _sortedCacheKey) return cached;

    final sorted = List<ComputerDetails>.from(source)
      ..sort((a, b) => rank(a).compareTo(rank(b)));
    _sortedCache = sorted;
    _sortedCacheKey = key;
    return sorted;
  }

  void _startHealthLoop() {
    _healthLoop?.stop();
    _healthLoop = ServerHealthLoop(
      context: context,
      onSessionLost: () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session expired — please sign in again'),
          ),
        );
      },
    )..start();
  }

  Future<void> _pickBackground(ComputerDetails computer) async {
    final savedPath = await ServerProfileImages.pick(computer.uuid);
    if (savedPath == null || !mounted) return;
    setState(() => _bgPaths[computer.uuid] = savedPath);
  }

  Future<void> _removeBackground(ComputerDetails computer) async {
    await ServerProfileImages.remove(computer.uuid);
    if (!mounted) return;
    setState(() => _bgPaths.remove(computer.uuid));
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final isLight = tp.colors.isLight;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _showExitConfirm(context, tp);
      },
      child: Scaffold(
        backgroundColor: tp.background,
        extendBodyBehindAppBar: true,
        body: Consumer<ComputerProvider>(
          builder: (context, provider, _) {
            final computers = _sortedForDisplay(provider.computers);
            final currentComputer =
                computers.isNotEmpty && _currentPage < computers.length
                ? computers[_currentPage]
                : null;
            // The wallpaper comes from Preferences only. The per-server image
            // is a profile picture: it belongs inside the circle/card and used
            // to hijack the whole screen, which made the wallpaper setting look
            // broken whenever a server had one.
            final globalWallpaper = tp.focusWallpaper;
            String? effectiveFilePath;
            String effectiveAsset = currentComputer != null
                ? _focusDefaultAsset(_currentPage)
                : _focusDefaultAsset(0);
            if (globalWallpaper.isNotEmpty) {
              if (globalWallpaper.startsWith('asset:')) {
                effectiveAsset = globalWallpaper.substring(6);
              } else if (globalWallpaper.startsWith('file:')) {
                effectiveFilePath = globalWallpaper.substring(5);
              }
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                // ── Wallpaper ──
                _Wallpaper(
                  imagePath: effectiveFilePath,
                  assetPath: effectiveAsset,
                  fallbackColor: tp.background,
                  cacheWidth: tp.performanceMode ? 720 : 1920,
                ),

                // ── Particle or Wave overlay (background effect) ──
                if (!tp.reduceEffects)
                  if (tp.ambienceEffect == 'particles')
                    _ParticleOverlay(color: tp.accent, isLight: isLight)
                  else if (tp.ambienceEffect == 'waves')
                    _WaveOverlay(color: tp.accent, isLight: isLight),

                // ── Scrim overlay ──
                Container(
                  color: (isLight ? Colors.white : Colors.black).withValues(
                    alpha: 0.35,
                  ),
                ),

                // ── Content ──
                // No SafeArea: on Android we run immersiveSticky so the
                // notification bar is hidden. Using SafeArea would add
                // top padding equal to the status bar height, pushing
                // the card off-center. A small manual top padding keeps
                // the app bar away from the camera notch on non-Android.
                Padding(
                  padding: EdgeInsets.only(
                    top: io.Platform.isAndroid
                        ? 8.0
                        : MediaQuery.of(context).padding.top,
                  ),
                  child: Column(
                    children: [
                      _buildAppBar(tp),
                      if (computers.isEmpty && provider.isDiscovering)
                        _buildDiscoveryIndicator(tp),
                      Expanded(
                        child: computers.isEmpty
                            ? _buildEmptyState(tp)
                            : _buildPageView(computers, tp),
                      ),
                      // Page indicator dots
                      if (computers.length > 1)
                        _buildPageIndicator(computers.length, tp),
                      NowPlayingBanner(
                        onTap: () async {
                          final c = provider.activeSessionComputer;
                          if (c != null) {
                            _ambientEnabled = false;
                            UiSoundService.stopAmbience();
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AppViewScreen(computer: c),
                              ),
                            );
                            if (mounted) {
                              _ambientEnabled = true;
                              UiSoundService.restartAmbience();
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 24,
                  bottom:
                      MediaQuery.of(context).padding.bottom +
                      (provider.activeSessionApp == null ? 24 : 76),
                  child: FocusMusicMiniPlayer(
                    trackName: _standbyTrackName(tp),
                    colors: tp.colors,
                    scale: tp.focusMusicScale,
                    opacity: tp.focusMusicOpacity,
                  ),
                ),
                NotificationMirrorOverlay(
                  bottomOffset: provider.activeSessionApp == null ? 104 : 156,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── App Bar ──

  String _standbyTrackName(ThemeProvider tp) {
    if (tp.standbySound == 'custom') {
      return tp.standbyCustomName.isNotEmpty ? tp.standbyCustomName : 'Custom';
    }
    return tp.standbySound;
  }

  Widget _buildAppBar(ThemeProvider tp) {
    final isLight = tp.colors.isLight;
    final fgColor = isLight ? Colors.black87 : Colors.white;
    final auth = context.watch<AuthProvider>();
    final count = auth.isSignedIn ? 4 : 3;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // One flex child, not two. A `Flexible` title beside a `Spacer` splits
          // the free space between them: the loose Flexible claims half and
          // uses only what the title needs, so the leftover sat as dead space
          // and the actions never reached the right edge — obvious in
          // landscape, where there is the most free space to waste.
          //
          // Expanded takes all of it, keeping the title left and the actions
          // hard right, while FittedBox scales the title down instead of
          // overflowing once the ~208px action cluster crowds it.
          const Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: JujoBrandTitle(),
              ),
            ),
          ),
          FocusableIconButton(
            focusNode: _appBarFocusNodes[0],
            icon: Icons.more_vert,
            tooltip: 'More',
            color: fgColor,
            onPressed: () =>
                PcViewScreen.pendingTour.value ? null : _showMoreMenu(context),
            onNav: (dir) => _handleAppBarIconNav(0, dir, count),
          ),
          FocusableIconButton(
            focusNode: _appBarFocusNodes[1],
            icon: Icons.settings,
            tooltip: 'Settings',
            color: fgColor,
            onPressed: () async {
              _ambientEnabled = false;
              UiSoundService.stopAmbience();
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              if (!mounted) return;
              _ambientEnabled = true;
              UiSoundService.playAmbience();
              if (io.Platform.isAndroid) {
                SystemChrome.setEnabledSystemUIMode(
                  SystemUiMode.immersiveSticky,
                );
              }
            },
            onNav: (dir) => _handleAppBarIconNav(1, dir, count),
          ),
          const SizedBox(width: 4),
          if (!auth.isSignedIn)
            FocusableIconButton(
              focusNode: _appBarFocusNodes[2],
              icon: Icons.cloud_off,
              tooltip: 'Sign in to Jujo Cloud',
              color: fgColor,
              onPressed: () {
                _ambientEnabled = false;
                UiSoundService.stopAmbience();
                PcViewScreen.showCloudAuth(context);
              },
              onNav: (dir) => _handleAppBarIconNav(2, dir, count),
            )
          else ...[
            FocusableIconButton(
              focusNode: _appBarFocusNodes[2],
              icon: auth.isSyncing ? Icons.sync : Icons.cloud_done,
              tooltip: auth.isSyncing ? 'Syncing...' : 'Sync to cloud',
              color: fgColor,
              onPressed: auth.isSyncing
                  ? null
                  : () {
                      unawaited(auth.pushToCloud());
                    },
              onNav: (dir) => _handleAppBarIconNav(2, dir, count),
            ),
            const SizedBox(width: 4),
            FocusableIconButton(
              focusNode: _appBarFocusNodes[3],
              icon: Icons.account_circle,
              tooltip: 'Account',
              color: fgColor,
              onPressed: () => PcViewScreen.showAccountPicker(context, auth),
              onNav: (dir) => _handleAppBarIconNav(3, dir, count),
            ),
          ],
        ],
      ),
    );
  }

  // ── More menu (reuses PcViewScreen's dialog pattern) ──

  void _showMoreMenu(BuildContext context) {
    final motion = MotionPolicy.fromContext(
      context,
      context.read<ThemeProvider>(),
    );
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: motion.dialogDuration,
      transitionBuilder: (ctx, anim, _, child) {
        final scale = CurvedAnimation(
          parent: anim,
          curve: motion.standardCurve,
        );
        final fade = CurvedAnimation(
          parent: anim,
          curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(scale),
          child: FadeTransition(opacity: fade, child: child),
        );
      },
      pageBuilder: (ctx, _, _) => _FocusModeMenuDialog(parentContext: context),
    );
  }

  // ── Discovery indicator ──

  Widget _buildDiscoveryIndicator(ThemeProvider tp) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: tp.accentLight,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            l.searchingServers,
            style: TextStyle(
              color: tp.colors.isLight ? Colors.black45 : Colors.white60,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty state ──

  Widget _buildEmptyState(ThemeProvider tp) {
    final l = AppLocalizations.of(context);
    final isLight = tp.colors.isLight;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.computer,
            size: 64,
            color: isLight ? Colors.black26 : Colors.white24,
          ),
          const SizedBox(height: 16),
          Text(
            l.noServersFound,
            style: TextStyle(
              color: isLight ? Colors.black54 : Colors.white54,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l.makeSureSunshine,
            textAlign: TextAlign.center,
            style: TextStyle(
              // white38 is 3.6:1 — below the body-text floor.
              color: isLight ? Colors.black54 : Colors.white54,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ── Page View ──

  Widget _buildPageView(List<ComputerDetails> computers, ThemeProvider tp) {
    return Focus(
      focusNode: _pageViewFocusNode,
      autofocus: true,
      onFocusChange: (focused) {
        if (focused && _ambientEnabled && mounted) {
          UiSoundService.playAmbience();
        }
        // The card's glow used to track only `index == _currentPage`, so it
        // stayed lit while focus was up in the app bar and the screen looked
        // like two things were focused at once.
        if (mounted && focused != _pageViewHasFocus) {
          setState(() => _pageViewHasFocus = focused);
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        // Gamepad A / Enter → connect
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          if (_currentPage < computers.length) {
            _onComputerTapped(computers[_currentPage]);
          }
          return KeyEventResult.handled;
        }

        // Gamepad X → server options
        if (key == LogicalKeyboardKey.contextMenu ||
            key == LogicalKeyboardKey.gameButtonX) {
          if (_currentPage < computers.length) {
            _showServerOptions(computers[_currentPage]);
          }
          return KeyEventResult.handled;
        }

        // LB / Left → prev
        if (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.gameButtonLeft1) {
          if (_currentPage > 0) {
            _pageController.previousPage(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
            );
          }
          return KeyEventResult.handled;
        }

        // RB / Right → next
        if (key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.gameButtonRight1) {
          if (_currentPage < computers.length - 1) {
            _pageController.nextPage(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
            );
          }
          return KeyEventResult.handled;
        }

        // arrowUp → focus AppBar icons
        if (key == LogicalKeyboardKey.arrowUp) {
          _focusAppBarIcon(_activeAppBarIndex);
          return KeyEventResult.handled;
        }

        // Gamepad B / Back → exit focus mode (show menu)
        if (key == LogicalKeyboardKey.gameButtonB ||
            key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack) {
          _showExitConfirm(context, tp);
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: PageView.builder(
        controller: _pageController,
        itemCount: computers.length,
        onPageChanged: (i) {
          setState(() => _currentPage = i);
          UiSoundService.playUiMove();
          HapticFeedback.selectionClick();
        },
        physics: const BouncingScrollPhysics(),
        itemBuilder: (context, index) {
          final computer = computers[index];
          // Only show custom background when server is paired — avoids
          // flicker when server revokes pairing and poll toggles state.
          final bgPath = computer.isPaired ? _bgPaths[computer.uuid] : null;
          final layout = tp.ambienceLayout;
          if (layout == 'circular') {
            return _FocusServerCircle(
              computer: computer,
              bgPath: bgPath,
              index: index,
              onTap: () => _onComputerTapped(computer),
              onLongPress: () => _showServerOptions(computer),
              isSelected: index == _currentPage && _pageViewHasFocus,
            );
          }
          return _FocusServerCard(
            computer: computer,
            bgPath: bgPath,
            index: index,
            onTap: () => _onComputerTapped(computer),
            onLongPress: () => _showServerOptions(computer),
            isSelected: index == _currentPage && _pageViewHasFocus,
          );
        },
      ),
    );
  }

  // ── Page indicator ──

  Widget _buildPageIndicator(int count, ThemeProvider tp) {
    final isLight = tp.colors.isLight;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final active = i == _currentPage;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: active ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: active
                  ? tp.accent
                  : (isLight ? Colors.black26 : Colors.white24),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }

  // ── Server options dialog (delegates to shared ComputerOptionsDialog) ──

  void _showServerOptions(ComputerDetails computer) {
    ComputerOptionsDialog.show(
      context: context,
      computer: computer,
      profileImagePaths: _bgPaths,
      onPickProfileImage: _pickBackground,
      onRemoveProfileImage: _removeBackground,
    );
  }

  // ── Exit confirm ──

  void _showExitConfirm(BuildContext context, ThemeProvider tp) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tp.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(Icons.exit_to_app_rounded, color: tp.accentLight, size: 22),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Exit JUJO?',
                style: TextStyle(
                  color: tp.colors.isLight ? Colors.black87 : Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to exit?',
          style: TextStyle(
            color: tp.colors.isLight ? Colors.black54 : Colors.white70,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await setFocusModeEnabled(false);
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const PcViewScreen()),
                  (_) => false,
                );
              }
            },
            child: const Text('Switch to PC View'),
          ),
          TextButton(
            onPressed: () {
              if (io.Platform.isWindows ||
                  io.Platform.isMacOS ||
                  io.Platform.isLinux) {
                io.exit(0);
              } else {
                SystemNavigator.pop();
              }
            },
            child: const Text(
              'Exit App',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _focusAppBarIcon(int index, {int? activeCount}) {
    final count =
        activeCount ?? (context.read<AuthProvider>().isSignedIn ? 4 : 3);
    final clamped = index.clamp(0, count - 1);
    _activeAppBarIndex = clamped;
    _appBarFocusNodes[clamped].requestFocus();
  }

  void _handleAppBarIconNav(
    int index,
    LogicalKeyboardKey dir,
    int activeCount,
  ) {
    UiSoundService.playUiMove();
    HapticFeedback.selectionClick();

    if (dir == LogicalKeyboardKey.arrowLeft) {
      final next = index > 0 ? index - 1 : activeCount - 1;
      _focusAppBarIcon(next, activeCount: activeCount);
    } else if (dir == LogicalKeyboardKey.arrowRight) {
      final next = index < activeCount - 1 ? index + 1 : 0;
      _focusAppBarIcon(next, activeCount: activeCount);
    } else if (dir == LogicalKeyboardKey.arrowDown) {
      _pageViewFocusNode.requestFocus();
    }
  }
}

// Crisp (no blur) full-screen wallpaper. Decodes bounded via ResizeImage to
// keep memory in check; a dim scrim keeps foreground text readable.
class _Wallpaper extends StatelessWidget {
  final String? imagePath;
  final String assetPath;
  final Color fallbackColor;
  final int cacheWidth;

  const _Wallpaper({
    this.imagePath,
    required this.assetPath,
    required this.fallbackColor,
    required this.cacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    final ImageProvider base;
    if (imagePath != null && imagePath!.isNotEmpty) {
      base = FileImage(io.File(imagePath!));
    } else {
      base = AssetImage(assetPath);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: ResizeImage(base, width: cacheWidth),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(color: fallbackColor),
        ),
        // Readability scrim (replaces the old sigma-40 blur).
        Container(color: Colors.black.withValues(alpha: 0.35)),
      ],
    );
  }
}

class _FocusServerCard extends StatefulWidget {
  final ComputerDetails computer;
  final String? bgPath;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isSelected;

  const _FocusServerCard({
    required this.computer,
    this.bgPath,
    required this.index,
    required this.onTap,
    required this.onLongPress,
    this.isSelected = true,
  });

  @override
  State<_FocusServerCard> createState() => _FocusServerCardState();
}

class _FocusServerCardState extends State<_FocusServerCard>
    with TickerProviderStateMixin {
  late AnimationController _floatController;
  late Animation<double> _floatAnimation;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      duration: const Duration(milliseconds: 5500),
      vsync: this,
    );

    _floatAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOutSine),
    );

    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );
    _glowAnimation = Tween<double>(begin: 0.18, end: 0.40).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // Animation start/stop handled in build via didChangeDependencies-like
    // watch on ThemeProvider.reduceEffects so toggling takes effect live.
    final tp = context.read<ThemeProvider>();
    if (!tp.reduceEffects) {
      _floatController.repeat(reverse: true);
    }
    _syncGlow();
  }

  @override
  void didUpdateWidget(covariant _FocusServerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
    if (oldWidget.isSelected != widget.isSelected) _syncGlow();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reacts to the reduce-effects toggle. build() used to schedule a
    // post-frame callback for this on *every* rebuild, allocating a closure per
    // frame to re-check a value that changes about once a year.
    _syncAnimation();
  }

  void _syncAnimation() {
    final reduce = context.read<ThemeProvider>().reduceEffects;
    if (!reduce && !_floatController.isAnimating) {
      _floatController.repeat(reverse: true);
    } else if (reduce && _floatController.isAnimating) {
      _floatController.stop();
      _floatController.reset();
    }
  }

  void _syncGlow() {
    final reduce = context.read<ThemeProvider>().reduceEffects;
    if (widget.isSelected && !reduce) {
      if (!_glowController.isAnimating) _glowController.repeat(reverse: true);
    } else {
      _glowController.stop();
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final isLight = tp.colors.isLight;
    final l = AppLocalizations.of(context);
    final cloudSignedIn = context.watch<AuthProvider>().isSignedIn;

    final state = ServerTileState.of(
      context,
      widget.computer,
      cloudSignedIn: cloudSignedIn,
      offlineColor: isLight ? Colors.black26 : Colors.white24,
    );
    final isOnline = state.isOnline;
    final isPaired = state.isPaired;
    final connectionStatus = state.connectionStatus;
    final statusColor = state.statusColor;
    final statusText = state.statusText;
    final actionText = state.actionText;

    final reduceEffects = tp.reduceEffects;

    final isMacOS = io.Platform.isMacOS;
    final isAndroid = io.Platform.isAndroid;
    final maxWidth = isMacOS ? 420.0 : (isAndroid ? 340.0 : 370.0);
    final maxHeight = isMacOS ? 280.0 : (isAndroid ? 220.0 : 240.0);

    return Center(
      child: AnimatedBuilder(
        animation: _floatAnimation,
        builder: (context, child) {
          final floatOffset = reduceEffects
              ? 0.0
              : math.sin(_floatAnimation.value * math.pi * 2) * 6;
          return Transform.translate(
            offset: Offset(0, floatOffset),
            child: child,
          );
        },
        child: Semantics(
          container: true,
          button: true,
          label: state.semanticLabel,
          hint: actionText.isEmpty ? null : actionText,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: GestureDetector(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  maxHeight: maxHeight,
                ),
                child: AspectRatio(
                  aspectRatio: 1.55,
                  child: AnimatedBuilder(
                    animation: _glowAnimation,
                    builder: (context, child) {
                      // Dynamic bloom: zero glow when unfocused,,
                      // breathe animation only when focused/hovered.
                      final glowAlpha = widget.isSelected
                          ? _glowAnimation.value
                          : 0.0;
                      return Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 24,
                        ),
                        decoration: BoxDecoration(
                          color: tp.surface.withValues(
                            alpha: isLight ? 0.92 : 0.85,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isLight ? 0.12 : 0.4,
                              ),
                              blurRadius: 32,
                              offset: const Offset(0, 12),
                            ),
                            BoxShadow(
                              color: tp.accent.withValues(alpha: glowAlpha),
                              blurRadius: widget.isSelected ? 18 : 0,
                              spreadRadius: widget.isSelected ? 3 : 0,
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: child,
                      );
                    },
                    child: Stack(
                      children: [
                        // ── Background image: custom or asset fallback ──
                        Positioned.fill(
                          child:
                              (widget.bgPath != null &&
                                  widget.bgPath!.isNotEmpty)
                              ? Image.file(
                                  io.File(widget.bgPath!),
                                  fit: BoxFit.cover,
                                  cacheWidth: kFocusCardImageCacheWidth,
                                  excludeFromSemantics: true,
                                  errorBuilder: (_, _, _) => Image.asset(
                                    _focusDefaultAsset(widget.index),
                                    fit: BoxFit.cover,
                                    cacheWidth: kFocusCardImageCacheWidth,
                                    excludeFromSemantics: true,
                                  ),
                                )
                              : Image.asset(
                                  _focusDefaultAsset(widget.index),
                                  fit: BoxFit.cover,
                                  cacheWidth: kFocusCardImageCacheWidth,
                                  excludeFromSemantics: true,
                                ),
                        ),
                        // ── Gradient overlay (always present) ──
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.25),
                                  Colors.black.withValues(alpha: 0.65),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // ── Cloud label / More options (top-right) ──
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.computer.isCloud)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: CloudBadge(compact: true),
                                ),
                              _MoreOptionsButton(
                                onTap: widget.onLongPress,
                                iconSize: 20,
                              ),
                            ],
                          ),
                        ),
                        // ── Status chip + server name (bottom-left) ──
                        Positioned(
                          bottom: 10,
                          left: 10,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: statusColor.withValues(alpha: 0.55),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: statusColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                      statusText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: statusColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.computer.name,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                                maxLines: 1,
                                // Without this, `maxLines: 1` clips the name
                                // mid-glyph instead of ellipsizing it.
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (isPaired)
                                Text(
                                  connectionStatus,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: widget.computer.isCloud
                                        ? Colors.cyanAccent.withValues(
                                            alpha: 0.82,
                                          )
                                        : Colors.white54,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // ── Gamepad hints — outside AspectRatio so they survive landscape ──
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _GamepadHintsRow(
                  isOnline: isOnline,
                  actionText: actionText,
                  settingsLabel: l.settings,
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusServerCircle extends StatefulWidget {
  final ComputerDetails computer;
  final String? bgPath;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isSelected;

  const _FocusServerCircle({
    required this.computer,
    this.bgPath,
    required this.index,
    required this.onTap,
    required this.onLongPress,
    this.isSelected = true,
  });

  @override
  State<_FocusServerCircle> createState() => _FocusServerCircleState();
}

class _FocusServerCircleState extends State<_FocusServerCircle>
    with TickerProviderStateMixin {
  late AnimationController _floatController;
  late Animation<double> _floatAnimation;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      duration: const Duration(milliseconds: 5500),
      vsync: this,
    );
    _floatAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOutSine),
    );
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );
    _glowAnimation = Tween<double>(begin: 0.18, end: 0.40).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    final tp = context.read<ThemeProvider>();
    if (!tp.reduceEffects) {
      _floatController.repeat(reverse: true);
    }
    _syncGlow();
  }

  @override
  void didUpdateWidget(covariant _FocusServerCircle oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
    if (oldWidget.isSelected != widget.isSelected) _syncGlow();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reacts to the reduce-effects toggle. build() used to schedule a
    // post-frame callback for this on *every* rebuild, allocating a closure per
    // frame to re-check a value that changes about once a year.
    _syncAnimation();
  }

  void _syncAnimation() {
    final reduce = context.read<ThemeProvider>().reduceEffects;
    if (!reduce && !_floatController.isAnimating) {
      _floatController.repeat(reverse: true);
    } else if (reduce && _floatController.isAnimating) {
      _floatController.stop();
      _floatController.reset();
    }
  }

  void _syncGlow() {
    final reduce = context.read<ThemeProvider>().reduceEffects;
    if (widget.isSelected && !reduce) {
      if (!_glowController.isAnimating) _glowController.repeat(reverse: true);
    } else {
      _glowController.stop();
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncAnimation();
    });
    final isLight = tp.colors.isLight;
    final l = AppLocalizations.of(context);
    final cloudSignedIn = context.watch<AuthProvider>().isSignedIn;

    final state = ServerTileState.of(
      context,
      widget.computer,
      cloudSignedIn: cloudSignedIn,
      // The circle encodes offline as red on its border rather than a grey
      // status dot, so it overrides just that one colour.
      offlineColor: Colors.redAccent,
    );
    final isOnline = state.isOnline;
    final isPaired = state.isPaired;
    final connectionStatus = state.connectionStatus;
    final borderColor = state.statusColor;
    final actionText = state.actionText;
    final ipAddress = state.address;
    final reduceEffects = tp.reduceEffects;

    final isMacOS = io.Platform.isMacOS;
    final isAndroid = io.Platform.isAndroid;
    final circleSize = isMacOS ? 220.0 : (isAndroid ? 180.0 : 200.0);
    final borderWidth = 3.5;

    return Center(
      child: AnimatedBuilder(
        animation: _floatAnimation,
        builder: (context, child) {
          final floatOffset = reduceEffects
              ? 0.0
              : math.sin(_floatAnimation.value * math.pi * 2) * 6;
          return Transform.translate(
            offset: Offset(0, floatOffset),
            child: child,
          );
        },
        child: Semantics(
          container: true,
          button: true,
          label: state.semanticLabel,
          hint: actionText.isEmpty ? null : actionText,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Circular server portrait ──
              AnimatedBuilder(
                animation: _glowAnimation,
                builder: (context, child) {
                  // Dynamic bloom: zero glow when unfocused,,
                  // breathe animation only when focused/hovered.
                  final glowAlpha = widget.isSelected
                      ? _glowAnimation.value
                      : 0.0;
                  return Container(
                    width: circleSize + borderWidth * 2,
                    height: circleSize + borderWidth * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: borderColor,
                        width: borderWidth,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: borderColor.withValues(alpha: 0.35),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: tp.accent.withValues(alpha: glowAlpha),
                          blurRadius: widget.isSelected ? 18 : 0,
                          spreadRadius: widget.isSelected ? 3 : 0,
                        ),
                      ],
                    ),
                    child: child,
                  );
                },
                child: ClipOval(
                  child: SizedBox(
                    width: circleSize,
                    height: circleSize,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // ── Background image ──
                        (widget.bgPath != null && widget.bgPath!.isNotEmpty)
                            ? Image.file(
                                io.File(widget.bgPath!),
                                fit: BoxFit.cover,
                                cacheWidth: kFocusCircleImageCacheWidth,
                                excludeFromSemantics: true,
                                errorBuilder: (_, _, _) => Image.asset(
                                  _focusDefaultAsset(widget.index),
                                  fit: BoxFit.cover,
                                  cacheWidth: kFocusCircleImageCacheWidth,
                                  excludeFromSemantics: true,
                                ),
                              )
                            : Image.asset(
                                _focusDefaultAsset(widget.index),
                                fit: BoxFit.cover,
                                cacheWidth: kFocusCircleImageCacheWidth,
                                excludeFromSemantics: true,
                              ),
                        // ── Subtle vignette ──
                        Container(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.3),
                              ],
                              stops: const [0.6, 1.0],
                            ),
                          ),
                        ),
                        // ── Cloud label / More options (top-right area) ──
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.computer.isCloud)
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent.withValues(
                                      alpha: 0.15,
                                    ),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.blueAccent.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.cloud,
                                    size: 10,
                                    color: Colors.blueAccent,
                                  ),
                                ),
                              _MoreOptionsButton(
                                onTap: widget.onLongPress,
                                iconSize: 16,
                                scrim: true,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // ── Server name ──
              Text(
                widget.computer.name,
                style: TextStyle(
                  color: isLight
                      ? Colors.black87
                      : Colors.white.withValues(alpha: 0.9),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // ── IP address ──
              if (ipAddress.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  ipAddress,
                  style: TextStyle(
                    // This sits over user-chosen artwork, so there is no fixed
                    // background to measure against. white38 was 3.6:1 even on
                    // the darkest theme; white54 clears 4.5:1 there and gives
                    // the scrim something to work with over a bright poster.
                    color: isLight ? Colors.black54 : Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
              if (isPaired) ...[
                const SizedBox(height: 3),
                Text(
                  connectionStatus,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.computer.isCloud
                        ? Colors.cyanAccent.withValues(alpha: 0.82)
                        : (isLight ? Colors.black45 : Colors.white54),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              // ── Gamepad hints ──
              _GamepadHintsRow(
                isOnline: isOnline,
                actionText: actionText,
                settingsLabel: l.settings,
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

/// The overflow affordance on a server tile.
///
/// The glyph stays small so it doesn't crowd the artwork, but the hit area is a
/// full 48×48: the two hand-rolled versions this replaces were 20×20 and 24×24,
/// both under the WCAG 2.5.8 target size, and neither carried a label.
class _MoreOptionsButton extends StatelessWidget {
  const _MoreOptionsButton({
    required this.onTap,
    required this.iconSize,
    this.scrim = false,
  });

  final VoidCallback onTap;
  final double iconSize;

  /// Circular dark backing, for tiles where the icon sits directly on artwork.
  final bool scrim;

  @override
  Widget build(BuildContext context) {
    final isSpanish =
        AppLocalizations.of(context).locale.languageCode == 'es';
    final icon = Icon(
      Icons.more_vert,
      size: iconSize,
      color: scrim ? Colors.white70 : Colors.white54,
    );

    return Semantics(
      label: isSpanish ? 'Opciones del servidor' : 'Server options',
      button: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        containedInkWell: false,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: scrim
                ? Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: icon,
                  )
                : icon,
          ),
        ),
      ),
    );
  }
}

/// Renders pure-text gamepad hints (no borders, no background boxes).
/// Positioned outside the AspectRatio card so it survives landscape layout.
class _GamepadHintsRow extends StatelessWidget {
  final bool isOnline;
  final String actionText;
  final String settingsLabel;

  const _GamepadHintsRow({
    required this.isOnline,
    required this.actionText,
    required this.settingsLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (!isOnline && actionText.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isOnline) ...[
          const GamepadHintIcon('X', size: 18, opacity: 0.70),
          const SizedBox(width: 4),
          Text(
            settingsLabel,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(width: 10),
        ],
        if (actionText.isNotEmpty) ...[
          const GamepadHintIcon('A', size: 18, opacity: 0.70),
          const SizedBox(width: 4),
          Text(
            actionText,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }
}

class _ParticleOverlay extends StatefulWidget {
  final Color color;
  final bool isLight;

  const _ParticleOverlay({required this.color, required this.isLight});

  @override
  State<_ParticleOverlay> createState() => _ParticleOverlayState();
}

class _ParticleOverlayState extends State<_ParticleOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Particle> _particles = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
        seconds: 60,
      ), // 60s for extremely smooth slow loop
    )..repeat();

    // Optimize: Less particles on TV devices
    final particleCount = TvDetector.instance.isTV ? 8 : 22;
    final random = math.Random();
    for (var i = 0; i < particleCount; i++) {
      _particles.add(
        _Particle(
          x: random.nextDouble(),
          y: random.nextDouble(),
          size: 2.0 + random.nextDouble() * 3.0,
          // Speeds MUST be exact integers to wrap flawlessly at progress 1.0!
          // 1.0 = 1 full screen every 60s. 2.0 = 2 screens every 60s.
          speed: (1 + random.nextInt(3)).toDouble(),
          opacity: 0.1 + random.nextDouble() * 0.2,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      // The controller drives the painter directly. AnimatedBuilder would
      // rebuild the CustomPaint widget every frame to hand it a new double.
      child: CustomPaint(
        painter: _ParticlePainter(
          particles: _particles,
          progress: _controller,
          color: widget.color,
          isLight: widget.isLight,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _RibbonComponent {
  final double cycle;
  final double amp;
  final double speed;
  final double phase;
  final double phaseOffset;

  _RibbonComponent({
    required this.cycle,
    required this.amp,
    required this.speed,
    required this.phase,
    required this.phaseOffset,
  });
}

class _Ribbon {
  final double thickness;
  final double fillAlpha;
  final double strokeAlpha;
  final List<_RibbonComponent> components;

  _Ribbon({
    required this.thickness,
    required this.fillAlpha,
    required this.strokeAlpha,
    required this.components,
  });
}

class _WaveOverlay extends StatefulWidget {
  final Color color;
  final bool isLight;

  const _WaveOverlay({required this.color, required this.isLight});

  @override
  State<_WaveOverlay> createState() => _WaveOverlayState();
}

class _WaveOverlayState extends State<_WaveOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// Drives the painter directly. This used to be a plain field written through
  /// `setState`, which rebuilt the element subtree 60 times a second to change
  /// one double. Handing the notifier to `CustomPainter.repaint` repaints
  /// without rebuilding anything.
  final ValueNotifier<double> _time = ValueNotifier<double>(0);

  final List<_Ribbon> _ribbons = [];

  @override
  void initState() {
    super.initState();
    final numRibbons = TvDetector.instance.isTV ? 2 : 4;
    final random = math.Random();

    final baseFill = widget.isLight ? 0.03 : 0.06;
    final baseStroke = widget.isLight ? 0.12 : 0.25;

    for (int i = 0; i < numRibbons; i++) {
      _ribbons.add(
        _Ribbon(
          thickness: random.nextDouble() * 0.025 + 0.005,
          fillAlpha: baseFill * (1.0 - (i % 3) * 0.15),
          strokeAlpha: baseStroke * (1.0 - (i % 3) * 0.15),
          components: List.generate(
            4,
            (compIndex) => _RibbonComponent(
              cycle:
                  (random.nextDouble() * 1.5 + 0.2) * (compIndex * 0.6 + 1.0),
              amp:
                  (random.nextDouble() * 0.25 + 0.05) / (compIndex * 0.4 + 1.0),
              speed: random.nextDouble() * 0.3 + 0.06,
              phase: random.nextDouble() * math.pi * 2,
              phaseOffset: random.nextDouble() * 0.6 + 0.1,
            ),
          ),
        ),
      );
    }

    _ticker = createTicker((elapsed) {
      _time.value = elapsed.inMicroseconds / 1000000.0;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _WavePainter(
          time: _time,
          ribbons: _ribbons,
          color: widget.color,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  /// Animation clock. Passed to `super.repaint` so the canvas re-paints on each
  /// tick without the widget tree rebuilding.
  final ValueListenable<double> timeListenable;
  final List<_Ribbon> ribbons;
  final Color color;

  _WavePainter({
    required ValueListenable<double> time,
    required this.ribbons,
    required this.color,
  }) : timeListenable = time,
       super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    final time = timeListenable.value;
    final w = size.width;
    final h = size.height;
    const baseY = 0.5;

    // We sample x every 'step' pixels (similar to HTML w/150)
    final double step = w / 150.0;

    for (final ribbon in ribbons) {
      final fillPaint = Paint()
        ..color = color.withValues(alpha: ribbon.fillAlpha)
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.plus
        ..isAntiAlias = true;

      final strokePaint = Paint()
        ..color = color.withValues(alpha: ribbon.strokeAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..blendMode = BlendMode.plus
        ..isAntiAlias = true;

      final path = Path();

      // Top edge
      for (double x = 0; x <= w + step; x += step) {
        double nx = x / w;
        double nodeDist = (nx - 0.5).abs() * 2;
        double convergence = math.pow(nodeDist, 1.5) * 0.85 + 0.15;

        double y = h * baseY;
        for (final comp in ribbon.components) {
          y +=
              math.sin(
                nx * math.pi * 2 * comp.cycle - time * comp.speed + comp.phase,
              ) *
              (h * comp.amp * convergence);
        }

        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      // Bottom edge
      for (double x = w + step; x >= -step; x -= step) {
        double nx = x / w;
        double nodeDist = (nx - 0.5).abs() * 2;
        double convergence = math.pow(nodeDist, 1.5) * 0.85 + 0.15;

        double dynamicThickness =
            ribbon.thickness +
            math.sin(nx * math.pi * 2 - time * 0.9) * (ribbon.thickness * 0.2);
        double y = h * baseY + (h * dynamicThickness);

        for (final comp in ribbon.components) {
          y +=
              math.sin(
                nx * math.pi * 2 * comp.cycle -
                    time * comp.speed +
                    comp.phase +
                    comp.phaseOffset,
              ) *
              (h * comp.amp * convergence);
        }
        path.lineTo(x, y);
      }

      path.close();
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.ribbons != ribbons;
}

class _Particle {
  final double x;
  final double y;
  final double size;
  final double speed;
  final double opacity;

  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.opacity,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;

  /// Animation clock, also wired to `super.repaint`.
  final Animation<double> progressListenable;
  final Color color;
  final bool isLight;

  _ParticlePainter({
    required this.particles,
    required Animation<double> progress,
    required this.color,
    required this.isLight,
  }) : progressListenable = progress,
       super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final progress = progressListenable.value;
    final paint = Paint()
      ..color = color.withValues(alpha: isLight ? 0.15 : 0.25);

    for (final particle in particles) {
      final yOffset = (particle.y + progress * particle.speed) % 1.0;
      final x = particle.x * size.width;
      final y = yOffset * size.height;

      canvas.drawCircle(
        Offset(x, y),
        particle.size,
        paint
          ..color = color.withValues(
            alpha: particle.opacity * (isLight ? 0.72 : 1.0),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.isLight != isLight ||
      oldDelegate.particles != particles;
}

class _FocusModeMenuDialog extends StatelessWidget {
  final BuildContext parentContext;

  const _FocusModeMenuDialog({required this.parentContext});

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final l = AppLocalizations.of(context);
    final isLight = tp.colors.isLight;
    final size = MediaQuery.sizeOf(context);
    final compact = size.width > size.height || size.height < 430;
    final dialogWidth = compact
        ? (size.width - 28).clamp(280.0, 312.0).toDouble()
        : (size.width - 36).clamp(300.0, 332.0).toDouble();

    return Center(
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.gameButtonB ||
                key == LogicalKeyboardKey.escape ||
                key == LogicalKeyboardKey.goBack) {
              Navigator.pop(context);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: dialogWidth),
              child: Container(
                margin: EdgeInsets.symmetric(
                  horizontal: compact ? 12 : 18,
                  vertical: compact ? 10 : 14,
                ),
                decoration: BoxDecoration(
                  color: tp.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isLight ? 0.22 : 0.48,
                      ),
                      blurRadius: 24,
                      spreadRadius: 1,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: compact ? 14 : 18),
                      _FocusMenuTile(
                        order: 0,
                        autofocus: true,
                        icon: Icons.grid_view_rounded,
                        iconColor: tp.accent,
                        label: l.focusModeDisabled,
                        compact: compact,
                        onTap: () async {
                          Navigator.pop(context);
                          await setFocusModeEnabled(false);
                          if (parentContext.mounted) {
                            Navigator.pushAndRemoveUntil(
                              parentContext,
                              MaterialPageRoute(
                                builder: (_) => const PcViewScreen(),
                              ),
                              (_) => false,
                            );
                          }
                        },
                      ),
                      _FocusMenuTile(
                        order: 1,
                        icon: Icons.person_rounded,
                        iconColor: Colors.blueAccent,
                        label: l.myProfile,
                        compact: compact,
                        onTap: () async {
                          Navigator.pop(context);
                          if (parentContext.mounted) {
                            await Navigator.push(
                              parentContext,
                              MaterialPageRoute(
                                builder: (_) => const ProfileScreen(),
                              ),
                            );
                          }
                        },
                      ),
                      _FocusMenuTile(
                        order: 2,
                        icon: Icons.info_outline_rounded,
                        iconColor: Colors.tealAccent,
                        label: l.aboutAndCredits,
                        compact: compact,
                        onTap: () async {
                          Navigator.pop(context);
                          if (parentContext.mounted) {
                            await Navigator.push(
                              parentContext,
                              MaterialPageRoute(
                                builder: (_) => const AboutScreen(),
                              ),
                            );
                          }
                        },
                      ),
                      SizedBox(height: compact ? 14 : 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusMenuTile extends StatefulWidget {
  final int order;
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool compact;
  final bool autofocus;
  final VoidCallback onTap;

  const _FocusMenuTile({
    required this.order,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.compact = false,
    this.autofocus = false,
  });

  @override
  State<_FocusMenuTile> createState() => _FocusMenuTileState();
}

class _FocusMenuTileState extends State<_FocusMenuTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final isLight = tp.colors.isLight;
    final compact = widget.compact;

    return FocusTraversalOrder(
      order: NumericFocusOrder(widget.order.toDouble()),
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (f) => setState(() => _focused = f),
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
            duration: const Duration(milliseconds: 140),
            margin: EdgeInsets.fromLTRB(16, 0, 16, compact ? 6 : 8),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14,
              vertical: compact ? 9 : 11,
            ),
            decoration: BoxDecoration(
              color: _focused
                  ? Colors.white.withValues(alpha: isLight ? 0.55 : 0.12)
                  : (isLight
                        ? Colors.white.withValues(alpha: 0.92)
                        : tp.background.withValues(alpha: 0.36)),
              borderRadius: BorderRadius.circular(15),
              // The border used to be identical in both states, so on a gamepad
              // the only cue was a 12%-alpha fill shift — invisible across a
              // room. Focus now reads as tonal step + accent border + glow, the
              // same vocabulary the pc_view menu already used.
              border: Border.all(
                color: _focused
                    ? tp.accent
                    : (isLight ? Colors.black12 : Colors.white12),
                width: _focused ? 1.6 : 1,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: tp.accent.withValues(alpha: 0.30),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: compact ? 30 : 34,
                  height: compact ? 30 : 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.iconColor.withValues(alpha: 0.17),
                  ),
                  child: Icon(
                    widget.icon,
                    color: widget.iconColor,
                    size: compact ? 17 : 18,
                  ),
                ),
                SizedBox(width: compact ? 10 : 11),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: isLight
                          ? Colors.black87
                          : Colors.white.withValues(alpha: 0.90),
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 12.5 : 13.5,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: isLight ? Colors.black38 : Colors.white38,
                  size: compact ? 18 : 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


