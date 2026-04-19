import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/database/achievement_service.dart';
import '../../services/database/session_history_service.dart';
import '../../services/pro/pro_service.dart';
import 'achievements_screen.dart';

const _kAvatarIndexKey = 'user_avatar_index';
const _kCustomNameKey = 'user_custom_name';

const _kAvatarCount = 100;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _avatarIndex = 1;
  String _customName = '';
  bool _loadingProfile = true;

  int _totalPlaytimeSec = 0;
  int _gamesCount = 0;
  List<Map<String, Object?>> _recentSessions = const [];
  bool _loadingStats = true;
  int _sessionPage = 0;

  bool _loadingAchievements = true;

  final ScrollController _scrollController = ScrollController();

  final FocusNode _changeAvatarFocus = FocusNode(debugLabel: 'change-avatar');
  final FocusNode _changeNameFocus = FocusNode(debugLabel: 'change-name');
  final FocusNode _achievementsFocus = FocusNode(
    debugLabel: 'achievements-btn',
  );

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
    _changeAvatarFocus.addListener(() {
      if (_changeAvatarFocus.hasFocus) _scrollToTop();
    });
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadProfile(), _loadStats(), _loadAchievements()]);
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _avatarIndex = prefs.getInt(_kAvatarIndexKey) ?? 1;
        _customName = prefs.getString(_kCustomNameKey) ?? '';
        _loadingProfile = false;
      });
    }
  }

  Future<void> _loadStats() async {
    final totalSec = await SessionHistoryService.totalPlaytimeAllSec();
    final gamesCount = await SessionHistoryService.distinctGamesCount();
    final recent = await SessionHistoryService.recentSessions(limit: 100);
    if (mounted) {
      setState(() {
        _totalPlaytimeSec = totalSec;
        _gamesCount = gamesCount;
        _recentSessions = recent;
        _loadingStats = false;
      });
    }
  }

  Future<void> _loadAchievements() async {
    await AchievementService.instance.loadAll();
    final totalSec = await SessionHistoryService.totalPlaytimeAllSec();
    final gamesCount = await SessionHistoryService.distinctGamesCount();
    await AchievementService.instance.checkStatsAchievements(
      totalPlaytimeSec: totalSec,
      distinctGamesCount: gamesCount,
    );
    if (mounted) {
      setState(() => _loadingAchievements = false);
    }
  }

  Future<void> _saveAvatarIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kAvatarIndexKey, index);
  }

  Future<void> _saveName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCustomNameKey, name);
  }

  String _avatarAssetPath(int index) {
    return 'assets/images/avatar/$index.png';
  }

  void _showAvatarPicker(ThemeProvider tp) {
    int selectedIndex = _avatarIndex;
    const crossAxisCount = 6;
    final scrollController = ScrollController();

    void ensureVisible(int index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;
        final row = ((index - 1) / crossAxisCount).floor();
        final total = (_kAvatarCount / crossAxisCount).ceil();
        final viewH = scrollController.position.viewportDimension;
        final itemH = viewH / 5.5.clamp(1.0, total.toDouble());
        final centerOffset = row * itemH - (viewH / 2 - itemH / 2);
        scrollController.animateTo(
          centerOffset.clamp(0.0, scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      });
    }

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialog) {
            void confirmSelection() {
              setState(() => _avatarIndex = selectedIndex);
              _saveAvatarIndex(selectedIndex);
              Navigator.pop(dialogCtx);
            }

            return Focus(
              autofocus: true,
              onKeyEvent: (_, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.gameButtonB ||
                    key == LogicalKeyboardKey.escape ||
                    key == LogicalKeyboardKey.goBack) {
                  Navigator.pop(dialogCtx);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.gameButtonA ||
                    key == LogicalKeyboardKey.enter ||
                    key == LogicalKeyboardKey.select) {
                  confirmSelection();
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowRight) {
                  setDialog(() {
                    selectedIndex = selectedIndex < _kAvatarCount
                        ? selectedIndex + 1
                        : 1;
                  });
                  ensureVisible(selectedIndex);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowLeft) {
                  setDialog(() {
                    selectedIndex = selectedIndex > 1
                        ? selectedIndex - 1
                        : _kAvatarCount;
                  });
                  ensureVisible(selectedIndex);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowDown) {
                  setDialog(() {
                    final next = selectedIndex + crossAxisCount;
                    selectedIndex = next <= _kAvatarCount
                        ? next
                        : selectedIndex;
                  });
                  ensureVisible(selectedIndex);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowUp) {
                  setDialog(() {
                    final prev = selectedIndex - crossAxisCount;
                    selectedIndex = prev >= 1 ? prev : selectedIndex;
                  });
                  ensureVisible(selectedIndex);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Dialog(
                backgroundColor: tp.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 480,
                    maxHeight: 520,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ClipOval(
                            child: Image.asset(
                              _avatarAssetPath(selectedIndex),
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 72,
                                height: 72,
                                color: Colors.white10,
                                child: Center(
                                  child: Text(
                                    '$selectedIndex',
                                    style: TextStyle(
                                      color: tp.accentLight,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Text(
                          AppLocalizations.of(dialogCtx).chooseYourAvatar,
                          style: TextStyle(
                            color: tp.accentLight,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppLocalizations.of(dialogCtx).avatarNavHint,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: GridView.builder(
                            controller: scrollController,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  crossAxisSpacing: 6,
                                  mainAxisSpacing: 6,
                                  childAspectRatio: 1,
                                ),
                            itemCount: _kAvatarCount,
                            itemBuilder: (_, i) {
                              final avatarIdx = i + 1;
                              final isSelected = avatarIdx == selectedIndex;
                              final isCurrent = avatarIdx == _avatarIndex;
                              return GestureDetector(
                                onTap: () {
                                  setState(() => _avatarIndex = avatarIdx);
                                  _saveAvatarIndex(avatarIdx);
                                  Navigator.pop(dialogCtx);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 140),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? tp.accent
                                          : isCurrent
                                          ? tp.accentLight.withValues(
                                              alpha: 0.5,
                                            )
                                          : Colors.transparent,
                                      width: isSelected ? 3 : 1,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: tp.accent.withValues(
                                                alpha: 0.4,
                                              ),
                                              blurRadius: 12,
                                              spreadRadius: 1,
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: ClipOval(
                                    child: Image.asset(
                                      _avatarAssetPath(avatarIdx),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Center(
                                        child: Text(
                                          '$avatarIdx',
                                          style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 12,
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
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Ⓐ ${AppLocalizations.of(dialogCtx).ok}  Ⓑ ${AppLocalizations.of(dialogCtx).cancel}',
                              style: const TextStyle(
                                color: Colors.white24,
                                fontSize: 10,
                              ),
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
        );
      },
    );
  }

  void _showNameEditor(ThemeProvider tp, AuthProvider auth) {
    final defaultName = auth.displayName ?? 'JUJO Player';
    final controller = TextEditingController(
      text: _customName.isNotEmpty ? _customName : defaultName,
    );
    showDialog(
      context: context,
      builder: (ctx) {
        return Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
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
            title: Text(
              AppLocalizations.of(ctx).yourName,
              style: const TextStyle(color: Colors.white),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 32,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(ctx).playerName,
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                counterStyle: const TextStyle(color: Colors.white38),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: tp.accent, width: 1.5),
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white24, width: 1),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          AppLocalizations.of(ctx).cancel,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        final name = controller.text.trim();
                        setState(() => _customName = name);
                        _saveName(name);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: tp.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: tp.accent, width: 2),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          AppLocalizations.of(ctx).save,
                          style: TextStyle(
                            color: tp.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _changeAvatarFocus.dispose();
    _changeNameFocus.dispose();
    _achievementsFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final auth = context.watch<AuthProvider>();
    final isLoading = _loadingProfile || _loadingStats || _loadingAchievements;

    return Scaffold(
      backgroundColor: tp.background,
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).myProfile,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: tp.surface,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Focus(
                onKeyEvent: (_, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (key == LogicalKeyboardKey.gameButtonB ||
                      key == LogicalKeyboardKey.escape ||
                      key == LogicalKeyboardKey.goBack) {
                    Navigator.maybePop(context);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                  children: [
                    _buildAvatarSection(auth, tp),
                    const SizedBox(height: 24),
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(2),
                      child: _buildStatsRow(tp),
                    ),
                    const SizedBox(height: 28),
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(3),
                      child: _buildAchievementsButton(tp),
                    ),
                    if (_recentSessions.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      _sectionLabel(
                        AppLocalizations.of(context).recentSessions,
                        tp,
                      ),
                      const SizedBox(height: 12),
                      ..._buildPaginatedSessions(tp),
                      const SizedBox(height: 100),
                    ] else ...[
                      const SizedBox(height: 28),
                      _buildEmptyState(tp),
                      const SizedBox(height: 100),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAvatarSection(AuthProvider auth, ThemeProvider tp) {
    final displayName = _customName.isNotEmpty
        ? _customName
        : (auth.displayName ?? 'JUJO Player');

    final avatarWidget = GestureDetector(
      onTap: () => _showAvatarPicker(tp),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tp.background,
              border: Border.all(
                color: tp.accent.withValues(alpha: 0.45),
                width: 2,
              ),
            ),
            child: ClipOval(
              child: Image.asset(
                _avatarAssetPath(_avatarIndex),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(Icons.person, color: Colors.white54, size: 42),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: tp.accent,
                shape: BoxShape.circle,
                border: Border.all(color: tp.surface, width: 2),
              ),
              child: const Icon(Icons.edit, size: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: tp.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Center(child: avatarWidget),
          const SizedBox(height: 16),
          Text(
            displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (auth.email != null) ...[
            const SizedBox(height: 4),
            Text(
              auth.email!,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _pillBadge('JUJO Stream', tp.accent, tp.accentLight),
              const SizedBox(width: 8),
              _pillBadge(
                '${AchievementService.instance.totalPoints} XP',
                tp.secondary,
                Colors.white70,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FocusTraversalOrder(
                order: const NumericFocusOrder(0),
                child: _ProfileActionButton(
                  focusNode: _changeAvatarFocus,
                  autofocus: true,
                  label: AppLocalizations.of(context).changeAvatar,
                  accentColor: tp.accent,
                  onTap: () => _showAvatarPicker(tp),
                  onRight: () => _changeNameFocus.requestFocus(),
                ),
              ),
              const SizedBox(width: 12),
              FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: _ProfileActionButton(
                  focusNode: _changeNameFocus,
                  label: AppLocalizations.of(context).changeName,
                  accentColor: tp.accent,
                  onTap: () => _showNameEditor(tp, auth),
                  onLeft: () => _changeAvatarFocus.requestFocus(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pillBadge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg.withValues(alpha: 0.80),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildStatsRow(ThemeProvider tp) {
    final totalSessions = _recentSessions.length;
    return Focus(
      onFocusChange: (f) {
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.4,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      child: Builder(
        builder: (ctx) {
          final hasFocus = Focus.of(ctx).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: tp.surface,
              borderRadius: BorderRadius.circular(16),
              border: hasFocus
                  ? Border.all(
                      color: tp.accent.withValues(alpha: 0.5),
                      width: 1.5,
                    )
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _statCard(
                    AppLocalizations.of(context).totalTime,
                    SessionHistoryService.formatDuration(_totalPlaytimeSec),
                    Icons.timer_outlined,
                    tp,
                  ),
                ),
                Container(
                  width: 1,
                  height: 52,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                Expanded(
                  child: _statCard(
                    AppLocalizations.of(context).gamesLabel,
                    '$_gamesCount',
                    Icons.videogame_asset_outlined,
                    tp,
                  ),
                ),
                Container(
                  width: 1,
                  height: 52,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                Expanded(
                  child: _statCard(
                    AppLocalizations.of(context).sessionsLabel,
                    totalSessions > 0 ? '$totalSessions' : '0',
                    Icons.history_outlined,
                    tp,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statCard(
    String label,
    String value,
    IconData icon,
    ThemeProvider tp,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: tp.accent, size: 17),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, ThemeProvider tp) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: Colors.white38,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildAchievementsButton(ThemeProvider tp) {
    final svc = AchievementService.instance;
    final unlocked = svc.unlockedCount;
    final total = svc.achievements.length;
    final progress = total > 0 ? unlocked / total : 0.0;

    return Focus(
      focusNode: _achievementsFocus,
      onFocusChange: (f) {
        if (f) {
          Scrollable.ensureVisible(
            _achievementsFocus.context ?? context,
            alignment: 0.25,
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
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AchievementsScreen()),
          );
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final hasFocus = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AchievementsScreen()),
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: tp.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasFocus
                      ? tp.accent.withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.06),
                  width: hasFocus ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        AppLocalizations.of(context).achievementsSection,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star, color: Colors.amberAccent, size: 13),
                          const SizedBox(width: 3),
                          Text(
                            '${svc.totalPoints} XP',
                            style: const TextStyle(
                              color: Colors.amberAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.chevron_right,
                        color: Colors.white38,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(tp.accent),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppLocalizations.of(context).unlockedOf(unlocked, total),
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildPaginatedSessions(ThemeProvider tp) {
    final total = _recentSessions.length;
    final pageSize = ProService.proSessionHistoryPageSize;

    final totalPages = (total / pageSize).ceil().clamp(1, 999);
    final safePage = _sessionPage.clamp(0, totalPages - 1);
    if (safePage != _sessionPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _sessionPage = safePage);
      });
    }
    final startIdx = safePage * pageSize;
    final endIdx = (startIdx + pageSize).clamp(0, total);
    final pageItems = _recentSessions.sublist(startIdx, endIdx);

    final widgets = <Widget>[];
    for (int i = 0; i < pageItems.length; i++) {
      widgets.add(
        FocusTraversalOrder(
          order: NumericFocusOrder(4.0 + i),
          child: _FocusableSessionTile(
            session: pageItems[i],
            tp: tp,
            onShowDetail: () => _showSessionDetail(pageItems[i], tp),
          ),
        ),
      );
    }

    if (totalPages > 1) {
      widgets.add(
        FocusTraversalOrder(
          order: NumericFocusOrder(4.0 + pageItems.length),
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PaginationButton(
                  icon: Icons.chevron_left,
                  label: 'Prev',
                  enabled: safePage > 0,
                  accentColor: tp.accent,
                  onTap: () => setState(() => _sessionPage = safePage - 1),
                ),
                const SizedBox(width: 16),
                Text(
                  '${safePage + 1} / $totalPages',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 16),
                _PaginationButton(
                  icon: Icons.chevron_right,
                  label: 'Next',
                  enabled: safePage < totalPages - 1,
                  accentColor: tp.accent,
                  onTap: () => setState(() => _sessionPage = safePage + 1),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _buildEmptyState(ThemeProvider tp) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(
              Icons.history_outlined,
              color: tp.accent.withValues(alpha: 0.4),
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).noSessionsYet,
              style: const TextStyle(color: Colors.white54, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).playToSeeHistory,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showSessionDetail(Map<String, Object?> session, ThemeProvider tp) {
    final appName = session['app_name'] as String? ?? 'Unknown';
    final durationSec = (session['duration_sec'] as num?)?.toInt() ?? 0;
    final serverName = session['server_name'] as String? ?? '';
    final serverId = session['server_id'] as String? ?? '';
    final startMs = (session['start_time_ms'] as num?)?.toInt() ?? 0;
    final endMs = (session['end_time_ms'] as num?)?.toInt() ?? 0;
    final startDate = startMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(startMs)
        : null;
    final endDate = endMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(endMs)
        : null;

    String fmtDate(DateTime? d) {
      if (d == null) return '—';
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }

    showDialog(
      context: context,
      builder: (ctx) => Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
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
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.sports_esports_outlined,
                color: tp.accentLight,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  appName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow(
                'Server',
                serverName.isNotEmpty ? serverName : serverId,
                tp,
              ),
              _detailRow('Start', fmtDate(startDate), tp),
              _detailRow('End', fmtDate(endDate), tp),
              _detailRow(
                'Duration',
                SessionHistoryService.formatDuration(durationSec),
                tp,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                AppLocalizations.of(ctx).close,
                style: TextStyle(color: tp.accentLight),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, ThemeProvider tp) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusableSessionTile extends StatefulWidget {
  final Map<String, Object?> session;
  final ThemeProvider tp;
  final VoidCallback onShowDetail;

  const _FocusableSessionTile({
    required this.session,
    required this.tp,
    required this.onShowDetail,
  });

  @override
  State<_FocusableSessionTile> createState() => _FocusableSessionTileState();
}

class _FocusableSessionTileState extends State<_FocusableSessionTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final tp = widget.tp;
    final appName = s['app_name'] as String? ?? 'Unknown';
    final durationSec = (s['duration_sec'] as num?)?.toInt() ?? 0;
    final serverName = s['server_name'] as String? ?? '';
    final startMs = (s['start_time_ms'] as num?)?.toInt() ?? 0;
    final date = startMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(startMs)
        : null;
    final dateStr = date != null
        ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'
        : '';

    return Focus(
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.2,
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
          widget.onShowDetail();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onShowDetail,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: _focused ? tp.accent.withValues(alpha: 0.10) : tp.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _focused
                  ? tp.accent
                  : Colors.white.withValues(alpha: 0.06),
              width: _focused ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      serverName.isNotEmpty
                          ? '$dateStr · $serverName'
                          : dateStr,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                SessionHistoryService.formatDuration(durationSec),
                style: TextStyle(
                  color: tp.accentLight,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_focused) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, color: tp.accentLight, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PaginationButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final Color accentColor;
  final VoidCallback onTap;

  const _PaginationButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: enabled,
      onFocusChange: (f) {
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent || !enabled) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final hasFocus = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: enabled ? onTap : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: hasFocus
                    ? accentColor.withValues(alpha: 0.20)
                    : enabled
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hasFocus
                      ? accentColor
                      : enabled
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
                  width: hasFocus ? 2 : 1,
                ),
                boxShadow: hasFocus
                    ? [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.3),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: enabled
                        ? (hasFocus ? accentColor : Colors.white70)
                        : Colors.white24,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: enabled
                          ? (hasFocus ? Colors.white : Colors.white70)
                          : Colors.white24,
                      fontSize: 11,
                      fontWeight: hasFocus ? FontWeight.w700 : FontWeight.w500,
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
}

class _ProfileActionButton extends StatelessWidget {
  final FocusNode focusNode;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;
  final bool autofocus;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const _ProfileActionButton({
    required this.focusNode,
    required this.label,
    required this.accentColor,
    required this.onTap,
    this.autofocus = false,
    this.onLeft,
    this.onRight,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      autofocus: autofocus,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select) {
          onTap();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          onLeft?.call();
          return onLeft != null
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          onRight?.call();
          return onRight != null
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final hasFocus = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 22),
              decoration: BoxDecoration(
                color: hasFocus
                    ? accentColor.withValues(alpha: 0.13)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hasFocus
                      ? accentColor
                      : Colors.white.withValues(alpha: 0.12),
                  width: hasFocus ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: hasFocus ? Colors.white : Colors.white70,
                      fontSize: 13,
                      fontWeight: hasFocus ? FontWeight.w700 : FontWeight.w500,
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
}
