import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/theme_provider.dart';
import '../../services/database/achievement_service.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final svc = AchievementService.instance;
    final all = svc.achievements;
    final unlocked = svc.unlockedCount;
    final total = all.length;
    final progress = total > 0 ? unlocked / total : 0.0;

    return Focus(
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
      child: Scaffold(
        backgroundColor: tp.background,
        appBar: AppBar(
          title: Text(
            AppLocalizations.of(context).achievementsTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: tp.surface,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: CustomScrollView(
          slivers: [

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '$unlocked / $total',
                          style: TextStyle(
                            color: tp.accentLight,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: tp.accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: tp.accent.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star,
                                color: Colors.amberAccent,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${svc.totalPoints} XP',
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(tp.accent),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppLocalizations.of(context).completedPercentLabel(progress * 100),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.82,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => FocusTraversalOrder(
                    order: NumericFocusOrder(i.toDouble()),
                    child: _FocusableAchievementChip(
                      achievement: all[i],
                      tp: tp,
                      autofocus: i == 0,
                    ),
                  ),
                  childCount: all.length,
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

class _FocusableAchievementChip extends StatefulWidget {
  final Achievement achievement;
  final ThemeProvider tp;
  final bool autofocus;

  const _FocusableAchievementChip({
    required this.achievement,
    required this.tp,
    this.autofocus = false,
  });

  @override
  State<_FocusableAchievementChip> createState() =>
      _FocusableAchievementChipState();
}

class _FocusableAchievementChipState extends State<_FocusableAchievementChip> {
  bool _focused = false;

  Color _difficultyColor(String difficulty) {
    return switch (difficulty) {
      'easy' => Colors.greenAccent,
      'medium' => widget.tp.accentLight,
      'hard' => Colors.orangeAccent,
      'legendary' => Colors.amberAccent,
      _ => widget.tp.accent,
    };
  }

  static IconData _achievementIcon(String id) {
    return switch (id) {
      'first_connection' => Icons.cable,
      'first_launch' => Icons.rocket_launch,
      'playtime_30min' => Icons.timer,
      'first_favorite' => Icons.favorite,
      'changed_theme' => Icons.palette,
      'playtime_5h' => Icons.local_fire_department,
      'first_collection' => Icons.collections_bookmark,
      'night_player' => Icons.dark_mode,
      'games_10' => Icons.diamond,
      'playtime_25h' => Icons.emoji_events,
      'wan_connect' => Icons.public,
      'auto_reconnect' => Icons.sync,
      'screenshot' => Icons.camera_alt,
      'collection_5games' => Icons.theater_comedy,
      'favorites_10' => Icons.star,
      'playtime_50h' => Icons.military_tech,
      'pip_mode' => Icons.picture_in_picture_alt,
      'night_sessions_10' => Icons.nightlight_round,
      'playtime_100h' => Icons.auto_awesome,
      'legend' => Icons.workspace_premium,
      _ => Icons.emoji_events,
    };
  }

  Widget _buildBadge(Achievement a, Color diffColor, bool locked) {
    final icon = _achievementIcon(a.id);
    final size = _focused ? 44.0 : 38.0;
    final iconSize = _focused ? 22.0 : 18.0;

    if (locked) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.06),
          border: Border.all(color: Colors.white12, width: 1.5),
        ),
        child: Icon(Icons.lock_outline, color: Colors.white24, size: iconSize),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            diffColor.withValues(alpha: 0.50),
            diffColor.withValues(alpha: 0.15),
          ],
        ),
        border: Border.all(
          color: diffColor.withValues(alpha: _focused ? 0.90 : 0.55),
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: diffColor.withValues(alpha: _focused ? 0.55 : 0.25),
            blurRadius: _focused ? 14 : 8,
            spreadRadius: _focused ? 2 : 0,
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.achievement;
    final tp = widget.tp;
    final locked = !a.isUnlocked;
    final diffColor = _difficultyColor(a.difficulty);
    final locale = Localizations.localeOf(context).languageCode;

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.4,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        }
      },
      child: Tooltip(
        message: a.localizedDescription(locale),
        preferBelow: false,
        textStyle: const TextStyle(color: Colors.white, fontSize: 11),
        decoration: BoxDecoration(
          color: widget.tp.background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            gradient: locked
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      diffColor.withValues(alpha: _focused ? 0.35 : 0.20),
                      tp.surface.withValues(alpha: 0.60),
                    ],
                  ),
            color: locked
                ? (_focused
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.white.withValues(alpha: 0.04))
                : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused
                  ? Colors.white
                  : locked
                      ? Colors.white.withValues(alpha: 0.08)
                      : diffColor.withValues(alpha: 0.50),
              width: _focused ? 2.0 : 1.2,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: (locked ? tp.accent : diffColor)
                          .withValues(alpha: 0.40),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : locked
                    ? null
                    : [
                        BoxShadow(
                          color: diffColor.withValues(alpha: 0.20),
                          blurRadius: 8,
                        ),
                      ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildBadge(a, diffColor, locked),
                const SizedBox(height: 5),
                Text(
                  a.localizedTitle(locale),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: locked
                        ? (_focused ? Colors.white54 : Colors.white24)
                        : Colors.white,
                    fontSize: _focused ? 10 : 9,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${a.points} XP',
                  style: TextStyle(
                    color: locked
                        ? (_focused ? Colors.white30 : Colors.white12)
                        : diffColor,
                    fontSize: _focused ? 9 : 8,
                    fontWeight: FontWeight.w700,
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
