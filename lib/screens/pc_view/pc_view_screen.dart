import 'dart:async';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import '../../l10n/app_localizations.dart';
import '../../models/computer_details.dart';
import '../../providers/computer_provider.dart';
import '../../providers/plugins_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/tv/tv_detector.dart';
import '../../services/input/gamepad_button_helper.dart';
import '../../widgets/now_playing_banner.dart';
import '../../widgets/computer_options_dialog.dart';
import '../../widgets/pairing_dialog.dart';
import '../about/about_screen.dart';
import '../app_view/app_view_screen.dart';
import '../companion/companion_qr_screen.dart';
import '../settings/device_flow_screen.dart';
import '../settings/profile_screen.dart';
import '../settings/settings_screen.dart';
import '../../providers/auth_provider.dart';
import '../../services/audio/ui_sound_service.dart';
import '../../widgets/tour_overlay.dart';
import 'focus_mode_screen.dart';

class PcViewScreen extends StatefulWidget {
  const PcViewScreen({super.key});

  static final pendingTour = ValueNotifier<bool>(false);

  @override
  State<PcViewScreen> createState() => _PcViewScreenState();
}

class _PcViewScreenState extends State<PcViewScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final FocusNode _screenFocusNode = FocusNode(debugLabel: 'pc-view-screen');
  bool _focusRequested = false;
  bool _autoConnectAttempted = false;

  final _iconFocusNodes = List.generate(
    2,
    (i) => FocusNode(debugLabel: 'appbar-icon-$i'),
  );

  List<FocusNode> _gridFocusNodes = [];
  int _lastComputerCount = -1;

  int _activeSectionIndex = 0;

  final Map<String, String> _computerBgPaths = {};
  bool _rearrangeMode = false;
  int? _selectedRearrangeIndex;
  AnimationController? _shakeController;

  final _tourSettingsKey = GlobalKey(debugLabel: 'tour-settings-btn');
  final _tourMoreKey = GlobalKey(debugLabel: 'tour-more-btn');
  final _tourServerCardKey = GlobalKey(debugLabel: 'tour-server-card');

  static String _bgPrefKey(String uuid) => 'computer_bg_$uuid';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..repeat(reverse: true);
    _shakeController!.stop();

    if (!TvDetector.instance.isTV) {
      SystemChrome.setPreferredOrientations([]);
    }
    if (io.Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ComputerProvider>().startDiscovery();
      _loadAllBgPaths();
      PcViewScreen.pendingTour.addListener(_onPendingTour);
      _scheduleAutoConnect();
    });
  }

  Future<void> _loadAllBgPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final all = prefs.getKeys();
    final updated = <String, String>{};
    for (final key in all) {
      if (key.startsWith('computer_bg_')) {
        final val = prefs.getString(key);
        if (val != null && val.isNotEmpty) {
          final uuid = key.substring('computer_bg_'.length);
          updated[uuid] = val;
        }
      }
    }
    if (!mounted) return;
    setState(
      () => _computerBgPaths
        ..clear()
        ..addAll(updated),
    );
  }

  Future<void> _pickComputerBackground(ComputerDetails computer) async {
    String? path;

    if (io.Platform.isMacOS) {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        path = result.files.single.path;
      }
    } else {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      path = picked?.path;
    }

    if (path == null || path.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bgPrefKey(computer.uuid), path);
    if (!mounted) return;
    final savedPath = path;
    setState(() => _computerBgPaths[computer.uuid] = savedPath);
  }

  Future<void> _removeComputerBackground(ComputerDetails computer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bgPrefKey(computer.uuid));
    if (!mounted) return;
    setState(() => _computerBgPaths.remove(computer.uuid));
  }

  void _syncGridFocusNodes(int totalGridItems) {
    if (totalGridItems == _lastComputerCount) return;

    for (var i = totalGridItems; i < _gridFocusNodes.length; i++) {
      _gridFocusNodes[i].dispose();
    }
    if (totalGridItems > _gridFocusNodes.length) {
      _gridFocusNodes = [
        ..._gridFocusNodes,
        ...List.generate(
          totalGridItems - _gridFocusNodes.length,
          (i) =>
              FocusNode(debugLabel: 'grid-item-${_gridFocusNodes.length + i}'),
        ),
      ];
    } else {
      _gridFocusNodes = _gridFocusNodes.sublist(0, totalGridItems);
    }
    _lastComputerCount = totalGridItems;
  }

  void _focusIcon(int index) {
    final clamped = index.clamp(0, _iconFocusNodes.length - 1);
    _activeSectionIndex = clamped;
    _iconFocusNodes[clamped].requestFocus();
  }

  void _focusGridItem(int index) {
    if (_gridFocusNodes.isEmpty) return;
    final clamped = index.clamp(0, _gridFocusNodes.length - 1);
    _activeSectionIndex = clamped;
    _gridFocusNodes[clamped].requestFocus();
  }

  void _onPendingTour() {
    if (!PcViewScreen.pendingTour.value) return;
    PcViewScreen.pendingTour.value = false;
    if (mounted) Future.delayed(const Duration(milliseconds: 600), _startTour);
  }

  void _scheduleAutoConnect() {
    if (_autoConnectAttempted) return;
    if (PcViewScreen.pendingTour.value) return;
    _autoConnectAttempted = true;
    _tryAutoConnect(0);
  }

  void _tryAutoConnect(int attempt) {
    if (!mounted || attempt >= 12) return;
    final provider = context.read<ComputerProvider>();
    final uuid = provider.primaryServerUuid;
    if (uuid == null) {
      // Provider still loading persisted data â€” retry shortly
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _tryAutoConnect(attempt + 1);
      });
      return;
    }
    final server = provider.primaryServer;
    if (server != null && server.isReachable && server.isPaired) {
      _onComputerTapped(server);
      return;
    }
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      _tryAutoConnect(attempt + 1);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-apply fullscreen on resume — Android may restore the notification bar
      // after returning from system dialogs, file pickers, or app switcher.
      if (io.Platform.isAndroid) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Intentionally do NOT reset SystemUiMode here. Flutter initializes the
    // pushed route (e.g. FocusModeScreen) BEFORE disposing the popped one,
    // so calling `edgeToEdge` in dispose would race with the new screen's
    // `immersiveSticky` call and make the notification bar reappear.
    // Each destination screen owns its own UI mode.
    PcViewScreen.pendingTour.removeListener(_onPendingTour);
    _screenFocusNode.dispose();
    _shakeController?.dispose();
    for (final n in _iconFocusNodes) {
      n.dispose();
    }
    for (final n in _gridFocusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _showExitConfirm(context, tp);
      },
      child: Scaffold(
        backgroundColor: tp.background,
        appBar: AppBar(
          title: _rearrangeMode
              ? Text(
                  AppLocalizations.of(context).rearrangeServers,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    letterSpacing: 0.8,
                  ),
                )
              : const Text(
                  'JujoStream',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 22,
                    letterSpacing: 1.2,
                  ),
                ),
          backgroundColor: tp.surface,
          foregroundColor: tp.colors.isLight ? Colors.black87 : Colors.white,
          elevation: 0,
          actions: _rearrangeMode
              ? [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _rearrangeMode = false;
                        _selectedRearrangeIndex = null;
                        _shakeController?.stop();
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppLocalizations.of(context).layoutSaved,
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Text(
                      AppLocalizations.of(context).done,
                      style: TextStyle(
                        color: tp.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ]
              : [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _FocusableIconBtn(
                        key: _tourMoreKey,
                        focusNode: _iconFocusNodes[0],
                        icon: Icons.more_vert,
                        tooltip: 'More options',
                        onPressed: () => _showMoreMenu(context),
                        onNav: (dir) => _handleIconNav(0, dir),
                      ),
                    ],
                  ),
                  _FocusableIconBtn(
                    key: _tourSettingsKey,
                    focusNode: _iconFocusNodes[1],
                    icon: Icons.settings,
                    tooltip: 'Settings',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      );
                    },
                    onNav: (dir) => _handleIconNav(1, dir),
                  ),
                  const SizedBox(width: 8),
                ],
        ),
        body: Consumer<ComputerProvider>(
          builder: (context, provider, child) {
            final totalGridItems = provider.computers.length + 1;
            _syncGridFocusNodes(totalGridItems);

            if (!_focusRequested) {
              _focusRequested = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _focusIcon(0);
              });
            }

            return Column(
              children: [
                if (provider.computers.isEmpty && provider.isDiscovering)
                  _buildDiscoveryBanner(),
                Expanded(child: _buildComputerGrid(provider)),

                if (_rearrangeMode) _buildRearrangeHintBanner(),

                NowPlayingBanner(
                  onTap: () {
                    final computer = provider.activeSessionComputer;
                    if (computer != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AppViewScreen(computer: computer),
                        ),
                      );
                    }
                  },
                ),
              ],
            );
          },
        ),
        floatingActionButton: null,
      ),
    );
  }

  Widget _buildRearrangeHintBanner() {
    final tp = context.read<ThemeProvider>();
    final isSelected = _selectedRearrangeIndex != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: tp.surfaceVariant.withValues(alpha: 0.95),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 20,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GamepadHintIcon('A', size: 16),
              const SizedBox(width: 6),
              Text(
                isSelected ? 'Drop here' : 'Select',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GamepadHintIcon('B', size: 16),
              const SizedBox(width: 6),
              Text(
                isSelected ? 'Cancel' : 'Exit',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (!isSelected)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.touch_app, size: 16, color: Colors.white54),
                const SizedBox(width: 6),
                const Text(
                  'Tap to select',
                  style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.touch_app, size: 16, color: Colors.white54),
                const SizedBox(width: 6),
                const Text(
                  'Tap to place',
                  style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _showMoreMenu(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 420),
      transitionBuilder: (ctx, anim, _, child) {
        final bounce = CurvedAnimation(parent: anim, curve: Curves.elasticOut);
        final fade = CurvedAnimation(
          parent: anim,
          curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.72, end: 1.0).animate(bounce),
          child: FadeTransition(opacity: fade, child: child),
        );
      },
      pageBuilder: (ctx, _, _) =>
          _MainMenuDialog(
            parentContext: context,
            onStartTour: _startTour,
            onRearrange: _startRearrangeMode,
          ),
    );
  }

  void _startRearrangeMode() {
    setState(() {
      _rearrangeMode = true;
      _selectedRearrangeIndex = null;
      _shakeController?.repeat(reverse: true);
    });
  }

  void _handleRearrangeCancel() {
    if (_selectedRearrangeIndex != null) {
      setState(() => _selectedRearrangeIndex = null);
      UiSoundService.playUiMove();
    } else {
      setState(() {
        _rearrangeMode = false;
        _selectedRearrangeIndex = null;
        _shakeController?.stop();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).layoutSaved),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleRearrangeSelect(int index, ComputerProvider provider) {
    if (_selectedRearrangeIndex == null) {
      setState(() => _selectedRearrangeIndex = index);
      UiSoundService.playClick();
    } else {
      provider.reorderComputers(_selectedRearrangeIndex!, index);
      setState(() => _selectedRearrangeIndex = null);
      UiSoundService.playClick();
    }
  }

  void _startTour() {
    TourController.instance.start([
      TourStep(
        title: 'Welcome to JUJO Stream',
        desc:
            'Your detected game servers appear right here. Select one to start playing instantly, or press X/Square on your gamepad to configure it.',
        targetKey: _tourServerCardKey,
        spotRadius: 56,
        tooltipAbove: false,
      ),
      TourStep(
        title: 'Focus Mode & Profile',
        desc:
            'Tap the ⋮ menu to toggle Focus Mode, a beautiful distraction-free interface perfect for TVs. You can also sign in here to scan a QR code and configure JUJO from your phone.',
        targetKey: _tourMoreKey,
        spotRadius: 32,
      ),
      TourStep(
        title: 'Customize Your Vibe',
        desc:
            'Open Settings to change color schemes (like deBoosy or Midnight), pick background effects (Waves or Particles), and tweak your streaming quality.',
        targetKey: _tourSettingsKey,
        spotRadius: 32,
      ),
      TourStep(
        title: 'Primary Server & Backgrounds',
        desc:
            'Long-press any server card (or press X/Square) to set a custom photo, or mark it as your Primary server. Your primary server connects automatically when the app starts.',
        targetKey: _tourServerCardKey,
        spotRadius: 56,
        tooltipAbove: false,
      ),
    ]);
  }

  Widget _buildBottomSheetHints(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GamepadHintIcon('A', size: 14),
          const SizedBox(width: 4),
          Text(
            l.ok,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(width: 16),
          GamepadHintIcon('B', size: 14),
          const SizedBox(width: 4),
          Text(
            l.cancel,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  void _doExit() {
    if (io.Platform.isWindows || io.Platform.isMacOS || io.Platform.isLinux) {
      io.exit(0);
    } else {
      SystemNavigator.pop();
    }
  }

  void _showExitConfirm(BuildContext context, ThemeProvider tp) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var selectedIndex = 0;

        Widget actionButton({
          required String label,
          required bool selected,
          required VoidCallback onTap,
          Color? bgColor,
          Color? textColor,
        }) {
          final bg = bgColor ?? tp.surfaceVariant;
          final fg = textColor ?? Colors.white;
          return Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? bg : tp.surface,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: bg.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? fg : Colors.white54,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        }

        return StatefulBuilder(
          builder: (ctx, setState) {
            void confirmSelection() {
              if (selectedIndex == 0) {
                Navigator.pop(ctx);
                return;
              }
              _doExit();
            }

            return Focus(
              autofocus: true,
              onKeyEvent: (_, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                final key = event.logicalKey;

                if (key == LogicalKeyboardKey.arrowLeft ||
                    key == LogicalKeyboardKey.arrowUp) {
                  setState(() => selectedIndex = 0);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowRight ||
                    key == LogicalKeyboardKey.arrowDown) {
                  setState(() => selectedIndex = 1);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.enter ||
                    key == LogicalKeyboardKey.select ||
                    key == LogicalKeyboardKey.gameButtonA) {
                  confirmSelection();
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.gameButtonB ||
                    key == LogicalKeyboardKey.escape ||
                    key == LogicalKeyboardKey.goBack) {
                  Navigator.pop(ctx);
                  return KeyEventResult.handled;
                }

                return KeyEventResult.ignored;
              },
              child: AlertDialog(
                backgroundColor: tp.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                title: Row(
                  children: [
                    Icon(
                      Icons.exit_to_app_rounded,
                      color: tp.accentLight,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Exit JUJO?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                content: const Text(
                  'Are you sure you want to exit?',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                actions: [
                  Row(
                    children: [
                      actionButton(
                        label: 'Cancel',
                        selected: selectedIndex == 0,
                        bgColor: tp.accent,
                        onTap: () {
                          setState(() => selectedIndex = 0);
                          Navigator.pop(ctx);
                        },
                      ),
                      const SizedBox(width: 10),
                      actionButton(
                        label: 'Exit',
                        selected: selectedIndex == 1,
                        bgColor: const Color(0xFFD84040),
                        textColor: Colors.white,
                        onTap: () {
                          setState(() => selectedIndex = 1);
                          _doExit();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDiscoveryBanner() {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.read<ThemeProvider>().accent.withValues(alpha: 0.12),
        border: Border(
          bottom: BorderSide(
            color: context.read<ThemeProvider>().accent.withValues(alpha: 0.13),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.read<ThemeProvider>().accentLight,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l.searchingServers,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComputerGrid(ComputerProvider provider) {
    final isTV = TvDetector.instance.isTV;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    final crossAxisCount = isTV ? 4 : (isLandscape ? 3 : 2);

    final childAspectRatio = isTV ? 1.33 : (isLandscape ? 1.08 : 0.9);
    final totalItems = provider.computers.length + 1;
    return RefreshIndicator(
      onRefresh: () async {
        await provider.stopDiscovery();
        await provider.startDiscovery();
      },
      child: GridView.builder(
        padding: EdgeInsets.all(isTV ? 24 : 16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: isTV ? 16 : (isLandscape ? 20 : 12),
          mainAxisSpacing: isTV ? 16 : 12,
        ),
        itemCount: totalItems,
        itemBuilder: (context, index) {
          final focusNode = index < _gridFocusNodes.length
              ? _gridFocusNodes[index]
              : null;

          if (index == provider.computers.length) {
            final addCard = _GridFocusableCard(
              focusNode: focusNode,
              onSelect: _rearrangeMode ? null : _showAddComputerDialog,
              onCancel: _rearrangeMode ? _handleRearrangeCancel : null,
              onNav: (dir) => _handleGridNav(index, dir, crossAxisCount),
              child: _AddServerCard(onTap: _rearrangeMode ? () {} : _showAddComputerDialog),
            );
            if (_rearrangeMode) {
              return Opacity(opacity: 0.3, child: addCard);
            }
            return addCard;
          }

          final isSelectedForRearrange = _selectedRearrangeIndex == index;

          Widget cardWrapper = _GridFocusableCard(
            key: index == 0 ? _tourServerCardKey : null,
            focusNode: focusNode,
            isSelected: isSelectedForRearrange,
            onSelect: _rearrangeMode ? () => _handleRearrangeSelect(index, provider) : () => _onComputerTapped(provider.computers[index]),
            onLongPress: _rearrangeMode ? null : () => _showComputerOptions(provider, provider.computers[index]),
            onCancel: _rearrangeMode ? _handleRearrangeCancel : null,
            onNav: (dir) => _handleGridNav(index, dir, crossAxisCount),
            child: _rearrangeMode
              ? RotationTransition(
                  turns: Tween(begin: -0.006, end: 0.006).animate(_shakeController!),
                  child: _ComputerCard(
                    computer: provider.computers[index],
                    customBgPath: provider.computers[index].isPaired
                        ? _computerBgPaths[provider.computers[index].uuid]
                        : null,
                    index: index,
                    onTap: () => _handleRearrangeSelect(index, provider),
                    onLongPress: () {},
                  ),
                )
              : _ComputerCard(
                  computer: provider.computers[index],
                  customBgPath: provider.computers[index].isPaired
                      ? _computerBgPaths[provider.computers[index].uuid]
                      : null,
                  index: index,
                  onTap: () => _onComputerTapped(provider.computers[index]),
                  onLongPress: () => _showComputerOptions(provider, provider.computers[index]),
                ),
          );

          return cardWrapper;
        },
      ),
    );
  }

  Future<void> _onComputerTapped(ComputerDetails computer) async {
    if (!computer.isReachable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).serverOffline)),
      );
      return;
    }

    if (!computer.isPaired) {
      final paired = await _showPairingDialog(computer);
      if (!mounted || !paired) {
        return;
      }
      // Pairing just completed — let the user manually re-enter the server
      // so the server has time to finish persisting the pairing internally.
      return;
    }

    // ── Entry gate: verify pairing is still valid on the server ─────
    // Prevents entering a server that revoked pairing server-side while
    // the client still had a stale "paired" cache.
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

    final prefs = await SharedPreferences.getInstance();
    final introEnabled =
        prefs.getBool('plugin_enabled_startup_intro_video') ?? false;
    final videoTrigger =
        prefs.getString(
          PluginsProvider.settingPref('startup_intro_video', 'video_trigger'),
        ) ??
        'before_app';
    if (introEnabled && videoTrigger == 'before_server') {
      final videoPath = prefs.getString(
        PluginsProvider.settingPref('startup_intro_video', 'video_path'),
      );
      if (videoPath != null &&
          videoPath.isNotEmpty &&
          await io.File(videoPath).exists()) {
        if (!mounted) return;
        await Navigator.push<void>(
          context,
          PageRouteBuilder(
            opaque: true,
            pageBuilder: (ctx, _, _) =>
                _BeforeServerVideo(videoPath: videoPath),
            transitionDuration: Duration.zero,
          ),
        );
        if (!mounted) return;
      }
    }

    if (!mounted) return;

    // Play server enter sound + strong haptic feedback
    UiSoundService.playServerEnter();
    HapticFeedback.heavyImpact();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AppViewScreen(computer: computer),
      ),
    );

    if (mounted && !TvDetector.instance.isTV) {
      SystemChrome.setPreferredOrientations([]);
    }
  }

  Future<bool> _showPairingDialog(ComputerDetails computer) async {
    final ok = await showPairingDialog(context, computer);
    if (ok && mounted) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.pairedSuccessfully(computer.name))),
      );
    }
    return ok;
  }

  void _showComputerOptions(
    ComputerProvider provider,
    ComputerDetails computer,
  ) {
    ComputerOptionsDialog.show(
      context: context,
      computer: computer,
      bgPaths: _computerBgPaths,
      onPickBackground: _pickComputerBackground,
      onRemoveBackground: _removeComputerBackground,
    );
  }

  void _showAddComputerDialog() {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Focus(
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.gameButtonB ||
                  event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.goBack)) {
            Navigator.pop(ctx);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AlertDialog(
          backgroundColor: ctx.read<ThemeProvider>().surface,
          title: Text(
            l.addPcManually,
            style: const TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: l.ipAddressHint,
              hintStyle: const TextStyle(color: Colors.white38),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: ctx.read<ThemeProvider>().accent),
              ),
            ),
            keyboardType: TextInputType.url,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  context.read<ComputerProvider>().addComputerManually(
                    controller.text.trim(),
                  );
                  Navigator.pop(ctx);
                }
              },
              child: Text(l.add),
            ),
          ],
        ),
      ),
    );
  }

  void _handleIconNav(int index, LogicalKeyboardKey dir) {
    // Audio + light haptic feedback on icon bar navigation
    UiSoundService.playUiMove();
    HapticFeedback.selectionClick();

    if (dir == LogicalKeyboardKey.arrowLeft) {
      final next = index > 0 ? index - 1 : _iconFocusNodes.length - 1;
      _focusIcon(next);
    } else if (dir == LogicalKeyboardKey.arrowRight) {
      final next = index < _iconFocusNodes.length - 1 ? index + 1 : 0;
      _focusIcon(next);
    } else if (dir == LogicalKeyboardKey.arrowDown) {
      _focusGridItem(0);
    } else if (dir == LogicalKeyboardKey.arrowUp) {
      if (_gridFocusNodes.isNotEmpty) {
        _focusGridItem(_gridFocusNodes.length - 1);
      }
    }
  }

  void _handleGridNav(int index, LogicalKeyboardKey dir, int crossAxisCount) {
    final total = _gridFocusNodes.length;
    if (total == 0) return;

    // Audio + light haptic feedback on every navigation move
    UiSoundService.playUiMove();
    HapticFeedback.selectionClick();

    if (dir == LogicalKeyboardKey.arrowRight) {
      final next = (index + 1) % total;
      _focusGridItem(next);
    } else if (dir == LogicalKeyboardKey.arrowLeft) {
      final next = (index - 1 + total) % total;
      _focusGridItem(next);
    } else if (dir == LogicalKeyboardKey.arrowDown) {
      final nextRow = index + crossAxisCount;
      if (nextRow < total) {
        _focusGridItem(nextRow);
      } else {
        _focusIcon(_activeSectionIndex.clamp(0, _iconFocusNodes.length - 1));
      }
    } else if (dir == LogicalKeyboardKey.arrowUp) {
      final prevRow = index - crossAxisCount;
      if (prevRow >= 0) {
        _focusGridItem(prevRow);
      } else {
        _focusIcon(_activeSectionIndex.clamp(0, _iconFocusNodes.length - 1));
      }
    }
  }
}

class _ComputerCard extends StatefulWidget {
  final ComputerDetails computer;
  final String? customBgPath;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ComputerCard({
    required this.computer,
    this.customBgPath,
    required this.index,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_ComputerCard> createState() => _ComputerCardState();
}

class _ComputerCardState extends State<_ComputerCard> {
  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final isOnline = widget.computer.isReachable;
    final isPaired = widget.computer.isPaired;
    return _buildCard(
      tp: tp,
      isOnline: isOnline,
      isPaired: isPaired,
      glowOpacity: isOnline ? 0.45 : 0.0,
      scale: 1.0,
    );
  }

  Widget _buildCard({
    required ThemeProvider tp,
    required bool isOnline,
    required bool isPaired,
    required double glowOpacity,
    required double scale,
  }) {
    final l = AppLocalizations.of(context);
    final statusColor = isOnline
        ? (isPaired ? Colors.greenAccent : Colors.orangeAccent)
        : Colors.white24;
    final statusText = isOnline
        ? (isPaired ? l.connected : l.notPaired)
        : l.disconnected;
    final actionText = isOnline ? (isPaired ? l.enter : l.pairAction) : '';
    final ipAddress = isOnline
        ? (widget.computer.activeAddress.isNotEmpty
              ? widget.computer.activeAddress
              : widget.computer.localAddress)
        : '';
    final hasBg =
        widget.customBgPath != null && widget.customBgPath!.isNotEmpty;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Transform.scale(
        scale: scale,
        child: Container(
          decoration: BoxDecoration(
            color: tp.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (hasBg) ...[
                  Positioned.fill(
                    child: Image.file(
                      io.File(widget.customBgPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),

                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x99000000), Color(0x88000000)],
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/focus/default_focus00${widget.index % 4}.jpg',
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x99000000), Color(0x88000000)],
                        ),
                      ),
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Icon(
                            Icons.more_vert,
                            size: 20,
                            color: Colors.white24,
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        widget.computer.name,
                        style: TextStyle(
                          color: isOnline ? Colors.white : Colors.white54,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (ipAddress.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          ipAddress,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: statusColor,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                statusText,
                                style: TextStyle(
                                  color: isOnline
                                      ? Colors.white70
                                      : Colors.white38,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isOnline)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Opacity(
                                    opacity: 0.45,
                                    child: GamepadHintIcon('X', size: 20),
                                  ),
                                ),
                              if (actionText.isNotEmpty) ...[
                                Opacity(
                                  opacity: 0.45,
                                  child: GamepadHintIcon('A', size: 20),
                                ),
                                const SizedBox(width: 4),
                                Opacity(
                                  opacity: 0.8,
                                  child: Text(
                                    actionText,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ],
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

class _BeforeServerVideo extends StatefulWidget {
  final String videoPath;
  const _BeforeServerVideo({required this.videoPath});

  @override
  State<_BeforeServerVideo> createState() => _BeforeServerVideoState();
}

class _BeforeServerVideoState extends State<_BeforeServerVideo> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final c = VideoPlayerController.file(io.File(widget.videoPath));
    try {
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      await c.setLooping(false);
      await c.play();
      c.addListener(() {
        if (!mounted) return;
        final v = c.value;
        if (v.isInitialized &&
            v.duration > Duration.zero &&
            v.position >= v.duration) {
          _dismiss();
        }
      });
      setState(() => _controller = c);
    } catch (_) {
      c.dispose();
      _dismiss();
    }
  }

  void _dismiss() {
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _dismiss,
        child: c != null && c.value.isInitialized
            ? Stack(
                fit: StackFit.expand,
                children: [
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: c.value.size.width,
                      height: c.value.size.height,
                      child: VideoPlayer(c),
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
                      label: const Text('Skip'),
                    ),
                  ),
                ],
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _AddServerCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddServerCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1.5,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.add_circle_outline,
              size: 32,
              color: Colors.white38,
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (ctx) => Text(
                AppLocalizations.of(ctx).addServer,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridFocusableCard extends StatefulWidget {
  final FocusNode? focusNode;
  final VoidCallback? onSelect;
  final VoidCallback? onLongPress;
  final VoidCallback? onCancel;
  final void Function(LogicalKeyboardKey dir) onNav;
  final Widget child;
  final bool isSelected;

  const _GridFocusableCard({
    super.key,
    this.focusNode,
    this.onSelect,
    this.onLongPress,
    this.onCancel,
    required this.onNav,
    required this.child,
    this.isSelected = false,
  });

  @override
  State<_GridFocusableCard> createState() => _GridFocusableCardState();
}

class _GridFocusableCardState extends State<_GridFocusableCard> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _hasFocus = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          widget.onSelect?.call();
          return KeyEventResult.handled;
        }

        if (key == LogicalKeyboardKey.contextMenu ||
            key == LogicalKeyboardKey.gameButtonX) {
          widget.onLongPress?.call();
          return KeyEventResult.handled;
        }

        if (key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.gameButtonB) {
          if (widget.onCancel != null) {
            widget.onCancel!();
            return KeyEventResult.handled;
          }
          Navigator.maybePop(context);
          return KeyEventResult.handled;
        }

        if (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) {
          widget.onNav(key);
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: (_hasFocus || widget.isSelected)
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.transparent,
          ),
          transform: (_hasFocus || widget.isSelected)
              ? (Matrix4.identity()..scale(1.01))
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}

class _FocusableIconBtn extends StatefulWidget {
  final FocusNode? focusNode;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final void Function(LogicalKeyboardKey dir)? onNav;

  const _FocusableIconBtn({
    super.key,
    this.focusNode,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.onNav,
  });

  @override
  State<_FocusableIconBtn> createState() => _FocusableIconBtnState();
}

class _FocusableIconBtnState extends State<_FocusableIconBtn> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select) {
          widget.onPressed();
          return KeyEventResult.handled;
        }

        if (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) {
          widget.onNav?.call(key);
          return KeyEventResult.handled;
        }

        if (key == LogicalKeyboardKey.gameButtonB ||
            key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.escape) {
          Navigator.maybePop(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        decoration: BoxDecoration(
          color: _focused
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: _focused
              ? Border.all(color: Colors.white54, width: 1.5)
              : null,
        ),
        child: IconButton(
          icon: Icon(widget.icon, color: Colors.white),
          tooltip: widget.tooltip,
          onPressed: widget.onPressed,
          focusNode: FocusNode(skipTraversal: true),
          style: IconButton.styleFrom(
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
        ),
      ),
    );
  }
}

class _MainMenuDialog extends StatefulWidget {
  final BuildContext parentContext;
  final VoidCallback? onStartTour;
  final VoidCallback? onRearrange;
  const _MainMenuDialog({required this.parentContext, this.onStartTour, this.onRearrange});

  @override
  State<_MainMenuDialog> createState() => _MainMenuDialogState();
}

class _MainMenuDialogState extends State<_MainMenuDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final tp = context.watch<ThemeProvider>();
    final auth = context.watch<AuthProvider>();
    final l = AppLocalizations.of(context);
    final isLight = tp.colors.isLight;
    final compact = size.width > size.height || size.height < 430;
    final dialogWidth = compact
        ? (size.width - 28).clamp(280.0, 312.0).toDouble()
        : (size.width - 36).clamp(300.0, 332.0).toDouble();
    final maxDialogHeight = size.height - media.padding.vertical - 24;
    final minDialogHeight =
        ((compact ? size.height * 0.34 : size.height * 0.39) * 1.10)
            .clamp(280.0, maxDialogHeight)
            .toDouble();

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
              constraints: BoxConstraints(
                maxWidth: dialogWidth,
                minHeight: minDialogHeight,
                maxHeight: maxDialogHeight,
              ),
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
                      Flexible(
                        child: Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: false,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            padding: EdgeInsets.only(bottom: compact ? 6 : 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(height: compact ? 0 : 2),
                                _DialogMenuItemTile(
                                  order: 0,
                                  autofocus: true,
                                  compact: compact,
                                  icon: Icons.person_outline,
                                  iconBubble: tp.accent.withValues(alpha: 0.17),
                                  iconColor: tp.accent,
                                  label: l.myProfile,
                                  accentColor: tp.accent,
                                  onTap: () {
                                    final nav = Navigator.of(
                                      widget.parentContext,
                                    );
                                    Navigator.pop(context);
                                    nav.push(
                                      MaterialPageRoute(
                                        builder: (_) => const ProfileScreen(),
                                      ),
                                    );
                                  },
                                ),
                                _DialogMenuItemTile(
                                  order: 1,
                                  compact: compact,
                                  icon: Icons.info_outline,
                                  iconBubble: tp.accent.withValues(alpha: 0.17),
                                  iconColor: tp.secondary,
                                  label: l.about,
                                  accentColor: tp.accent,
                                  onTap: () {
                                    final nav = Navigator.of(
                                      widget.parentContext,
                                    );
                                    Navigator.pop(context);
                                    nav.push(
                                      MaterialPageRoute(
                                        builder: (_) => const AboutScreen(),
                                      ),
                                    );
                                  },
                                ),
                                _DialogMenuItemTile(
                                  order: 2,
                                  compact: compact,
                                  icon: Icons.smartphone_outlined,
                                  iconBubble: tp.accentLight.withValues(
                                    alpha: 0.17,
                                  ),
                                  iconColor: tp.accent,
                                  label: l.configureFromPhoneBtn,
                                  accentColor: tp.accent,
                                  onTap: () {
                                    Navigator.pop(context);
                                    CompanionQrScreen.show(
                                      widget.parentContext,
                                    );
                                  },
                                ),
                                _DialogMenuItemTile(
                                  order: 3,
                                  compact: compact,
                                  icon: Icons.center_focus_strong_outlined,
                                  iconBubble: tp.accentLight.withValues(
                                    alpha: 0.17,
                                  ),
                                  iconColor: tp.accentLight,
                                  label: l.focusMode,
                                  accentColor: tp.accent,
                                  onTap: () async {
                                    Navigator.pop(context);
                                    await setFocusModeEnabled(true);
                                    // Force immersive BEFORE navigation so the
                                    // notification bar is never visible during
                                    // the route transition animation.
                                    if (io.Platform.isAndroid) {
                                      SystemChrome.setEnabledSystemUIMode(
                                        SystemUiMode.immersiveSticky,
                                      );
                                    }
                                    if (widget.parentContext.mounted) {
                                      Navigator.pushAndRemoveUntil(
                                        widget.parentContext,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const FocusModeScreen(),
                                        ),
                                        (_) => false,
                                      );
                                    }
                                  },
                                ),
                                _DialogMenuItemTile(
                                  order: 4,
                                  compact: compact,
                                  icon: Icons.grid_view_rounded,
                                  iconBubble: tp.accentLight.withValues(
                                    alpha: 0.17,
                                  ),
                                  iconColor: tp.accentLight,
                                  label: l.rearrangeServers,
                                  accentColor: tp.accent,
                                  onTap: () {
                                    Navigator.pop(context);
                                    widget.onRearrange?.call();
                                  },
                                ),
                                SizedBox(height: compact ? 6 : 10),
                                if (!auth.isSignedIn)
                                  _buildGoogleRow(tp, auth, compact: compact)
                                else
                                  _buildSignedInRow(tp, auth, compact: compact),
                                SizedBox(height: compact ? 20 : 24),
                              ],
                            ),
                          ),
                        ),
                      ),
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

  Widget _buildGoogleRow(
    ThemeProvider tp,
    AuthProvider auth, {
    required bool compact,
  }) {
    return _GoogleSignInButton(
      order: 3,
      compact: compact,
      label: 'Login with Google',
      accentColor: tp.accent,
      onTap: () async {
        Navigator.pop(context);
        final pc = widget.parentContext;
        if (TvDetector.instance.isTV) {
          if (pc.mounted) DeviceFlowScreen.show(pc);
          return;
        }
        final ok = await auth.signIn();
        if (!ok && pc.mounted && auth.deviceFlowAvailable) {
          DeviceFlowScreen.show(pc);
        }
      },
    );
  }

  Widget _buildSignedInRow(
    ThemeProvider tp,
    AuthProvider auth, {
    required bool compact,
  }) {
    final isLight = tp.colors.isLight;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 18),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: compact ? 8 : 9,
        ),
        decoration: BoxDecoration(
          color: isLight
              ? tp.background.withValues(alpha: 0.20)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isLight ? Colors.black12 : Colors.white12),
        ),
        child: Row(
          children: [
            if (auth.photoUrl != null)
              CircleAvatar(
                backgroundImage: NetworkImage(auth.photoUrl!),
                radius: 16,
              )
            else
              CircleAvatar(
                radius: 16,
                backgroundColor: tp.accent.withValues(alpha: 0.14),
                child: Icon(Icons.account_circle, color: tp.accent, size: 20),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auth.displayName ?? 'Google Account',
                    style: TextStyle(
                      color: isLight ? Colors.black87 : Colors.white,
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (auth.email != null)
                    Text(
                      auth.email!,
                      style: TextStyle(
                        color: isLight ? Colors.black54 : Colors.white54,
                        fontSize: compact ? 10 : 11,
                      ),
                    ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => auth.signOut(),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : 11,
                  vertical: compact ? 5 : 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Sign out',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCancel(ThemeProvider tp, {required bool compact}) {
    final isLight = tp.colors.isLight;
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, compact ? 5 : 8, 12, compact ? 8 : 12),
        child: Text(
          'Cancel',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isLight ? Colors.black54 : Colors.white54,
            fontSize: compact ? 13 : 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DialogMenuItemTile extends StatefulWidget {
  final int order;
  final IconData icon;
  final Color iconBubble;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;
  final bool autofocus;
  final bool compact;
  final Color accentColor;

  const _DialogMenuItemTile({
    required this.order,
    required this.icon,
    required this.iconBubble,
    required this.iconColor,
    required this.label,
    required this.onTap,
    required this.accentColor,
    this.compact = false,
    this.autofocus = false,
  });

  @override
  State<_DialogMenuItemTile> createState() => _DialogMenuItemTileState();
}

class _DialogMenuItemTileState extends State<_DialogMenuItemTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final isLight = tp.colors.isLight;
    final selected = _focused;
    final compact = widget.compact;

    return FocusTraversalOrder(
      order: NumericFocusOrder(widget.order.toDouble()),
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
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
            duration: const Duration(milliseconds: 140),
            margin: EdgeInsets.fromLTRB(16, 0, 16, compact ? 6 : 8),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14,
              vertical: compact ? 9 : 11,
            ),
            decoration: BoxDecoration(
              gradient: selected
                  ? LinearGradient(
                      colors: [
                        widget.accentColor.withValues(alpha: 0.78),
                        tp.accentLight.withValues(alpha: 0.95),
                      ],
                    )
                  : null,
              color: selected
                  ? null
                  : (isLight
                        ? Colors.white.withValues(alpha: 0.92)
                        : tp.background.withValues(alpha: 0.36)),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: selected
                    ? widget.accentColor.withValues(alpha: 0.55)
                    : (isLight ? Colors.black12 : Colors.white12),
                width: selected ? 1.6 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: widget.accentColor.withValues(alpha: 0.26),
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
                    color: selected
                        ? Colors.white.withValues(alpha: 0.22)
                        : widget.iconBubble,
                  ),
                  child: Icon(
                    widget.icon,
                    color: selected ? Colors.white : widget.iconColor,
                    size: compact ? 17 : 18,
                  ),
                ),
                SizedBox(width: compact ? 10 : 11),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : (isLight
                                ? Colors.black87
                                : Colors.white.withValues(alpha: 0.90)),
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 12.5 : 13.5,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.95)
                      : (isLight ? Colors.black38 : Colors.white38),
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

class _GoogleSignInButton extends StatefulWidget {
  final int order;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;
  final bool compact;

  const _GoogleSignInButton({
    required this.order,
    required this.label,
    required this.accentColor,
    required this.onTap,
    this.compact = false,
  });

  @override
  State<_GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<_GoogleSignInButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    return FocusTraversalOrder(
      order: NumericFocusOrder(widget.order.toDouble()),
      child: Focus(
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
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
            duration: const Duration(milliseconds: 140),
            margin: EdgeInsets.fromLTRB(16, 0, 16, compact ? 6 : 8),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14,
              vertical: compact ? 8 : 10,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(compact ? 12 : 14),
              border: Border.all(
                color: _focused
                    ? widget.accentColor.withValues(alpha: 0.85)
                    : const Color(0xFFDADCE0),
                width: _focused ? 1.6 : 1,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: widget.accentColor.withValues(alpha: 0.18),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              children: [
                Container(
                  width: compact ? 28 : 32,
                  height: compact ? 28 : 32,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 4 : 5),
                    child: Image.asset(
                      'assets/images/UI/logo/google_logo/g-logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                SizedBox(width: compact ? 10 : 12),
                Expanded(
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF3C4043),
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(width: compact ? 18 : 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
