import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/theme_provider.dart';

import '../auth/cloud_auth_screen.dart';

// ── Spacing tokens ────────────────────────────────────────────────────────────
class _S {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

// ── Radius token ──────────────────────────────────────────────────────────────
class _R {
  static const double lg = 20.0;
  static const double xl = 28.0;
  static const double full = 999.0;
}

// ═════════════════════════════════════════════════════════════════════════════
// Onboarding Screen
// ═════════════════════════════════════════════════════════════════════════════

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _scrollController = ScrollController();
  final _scrollOffset = ValueNotifier<double>(0.0);

  static const int _chapterCount = 4;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() => _scrollOffset.value = _scrollController.offset;

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────
  void _scrollNext() {
    final vh = MediaQuery.sizeOf(context).height;
    if (vh == 0) return;
    final page = (_scrollController.offset / vh).round();
    if (page < _chapterCount - 1) {
      _scrollController.animateTo(
        (page + 1) * vh,
        duration: const Duration(milliseconds: 580),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _scrollBack() {
    final vh = MediaQuery.sizeOf(context).height;
    if (vh == 0) return;
    final page = (_scrollController.offset / vh).round();
    if (page > 0) {
      _scrollController.animateTo(
        (page - 1) * vh,
        duration: const Duration(milliseconds: 580),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('first_run_shown', true);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const CloudAuthScreen(isFirstRun: true),
        ),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final tp = context.watch<ThemeProvider>();

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.gameButtonB): const DismissIntent(),
        LogicalKeySet(LogicalKeyboardKey.goBack): const DismissIntent(),
        LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
        LogicalKeySet(LogicalKeyboardKey.gameButtonRight1): const _NextIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowRight): const _NextIntent(),
        LogicalKeySet(LogicalKeyboardKey.gameButtonLeft1): const _PrevIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowLeft): const _PrevIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowDown): const _NextIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowUp): const _PrevIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              final vh = MediaQuery.sizeOf(context).height;
              final page = vh > 0
                  ? (_scrollController.offset / vh).round()
                  : 0;
              if (page < _chapterCount - 1) {
                _scrollController.animateTo(
                  (_chapterCount - 1) * vh,
                  duration: const Duration(milliseconds: 580),
                  curve: Curves.easeInOutCubic,
                );
              } else {
                _finish();
              }
              return true;
            },
          ),
          _NextIntent: CallbackAction<_NextIntent>(
            onInvoke: (_) {
              _scrollNext();
              return true;
            },
          ),
          _PrevIntent: CallbackAction<_PrevIntent>(
            onInvoke: (_) {
              _scrollBack();
              return true;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: tp.background,
            body: Stack(
              children: [
                // ── Ambient glow background ──────────────────────────────
                _AmbientGlow(scrollOffset: _scrollOffset, tp: tp),

                // ── Scrollable chapters ──────────────────────────────────
                CustomScrollView(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: size.height,
                        child: _HeroChapter(
                          scrollOffset: _scrollOffset,
                          chapterIndex: 0,
                          tp: tp,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: size.height,
                        child: _LatencyChapter(
                          scrollOffset: _scrollOffset,
                          chapterIndex: 1,
                          tp: tp,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: size.height,
                        child: _GamepadChapter(
                          scrollOffset: _scrollOffset,
                          chapterIndex: 2,
                          tp: tp,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: size.height,
                        child: _CloudChapter(
                          scrollOffset: _scrollOffset,
                          chapterIndex: 3,
                          tp: tp,
                          onGetStarted: _finish,
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Top branding bar ────────────────────────────────────
                _TopBar(onSkip: _finish),

                // ── Bottom pill nav ─────────────────────────────────────
                _BottomNav(
                  scrollOffset: _scrollOffset,
                  chapterCount: _chapterCount,
                  onNext: _scrollNext,
                  onBack: _scrollBack,
                  tp: tp,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Intent types ──────────────────────────────────────────────────────────────
class _NextIntent extends Intent {
  const _NextIntent();
}

class _PrevIntent extends Intent {
  const _PrevIntent();
}

// ═════════════════════════════════════════════════════════════════════════════
// Ambient Glow Background
// ═════════════════════════════════════════════════════════════════════════════

class _AmbientGlow extends StatelessWidget {
  final ValueNotifier<double> scrollOffset;
  final ThemeProvider tp;

  const _AmbientGlow({required this.scrollOffset, required this.tp});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: scrollOffset,
      builder: (context, offset, _) {
        final vh = MediaQuery.sizeOf(context).height;
        final page = vh > 0 ? (offset / vh).clamp(0.0, 3.0) : 0.0;

        final List<List<Color>> palettes = [
          [const Color(0xFF0F0C20), const Color(0xFF06040A)],
          [const Color(0xFF061528), const Color(0xFF0D061A)],
          [const Color(0xFF060B1E), const Color(0xFF130514)],
          [const Color(0xFF051710), const Color(0xFF0F061C)],
        ];

        final int cur = page.floor().clamp(0, 3);
        final int nxt = (cur + 1).clamp(0, 3);
        final double t = page - cur;

        Color lerp(int i) => Color.lerp(palettes[cur][i], palettes[nxt][i], t)!;

        return AnimatedContainer(
          duration: Duration.zero,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [lerp(0), lerp(1)],
            ),
          ),
          child: Stack(
            children: [
              // Primary orb
              Positioned(
                top: -100,
                left: -80,
                child: Container(
                  width: 500,
                  height: 500,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        tp.accent.withValues(alpha: 0.12),
                        tp.accent.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ).animate(onPlay: (c) => c.repeat(reverse: true))
                 .scale(
                   begin: const Offset(0.88, 0.88),
                   end: const Offset(1.12, 1.12),
                   duration: 5.seconds,
                   curve: Curves.easeInOut,
                 ),
              ),
              // Secondary orb
              Positioned(
                bottom: -80,
                right: -60,
                child: Container(
                  width: 380,
                  height: 380,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        tp.accentLight.withValues(alpha: 0.08),
                        tp.accentLight.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ).animate(onPlay: (c) => c.repeat(reverse: true))
                 .scale(
                   begin: const Offset(1.0, 1.0),
                   end: const Offset(0.80, 0.80),
                   duration: 4.2.seconds,
                   curve: Curves.easeInOut,
                 ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Top Branding Bar
// ═════════════════════════════════════════════════════════════════════════════

class _TopBar extends StatelessWidget {
  final VoidCallback onSkip;

  const _TopBar({required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _S.xl, vertical: _S.md),
          child: Row(
            children: [
              // Logo
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: const Icon(Icons.bolt, color: Colors.white70, size: 22),
              ),
              const SizedBox(width: 12),
              const Text(
                'JUJO.STREAM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.5,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white54,
                  padding: const EdgeInsets.symmetric(
                    horizontal: _S.md,
                    vertical: _S.sm,
                  ),
                ),
                child: const Text(
                  'Skip',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Bottom Pill Navigation
// ═════════════════════════════════════════════════════════════════════════════

class _BottomNav extends StatelessWidget {
  final ValueNotifier<double> scrollOffset;
  final int chapterCount;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final ThemeProvider tp;

  const _BottomNav({
    required this.scrollOffset,
    required this.chapterCount,
    required this.onNext,
    required this.onBack,
    required this.tp,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: _S.xl,
      left: 0,
      right: 0,
      child: ValueListenableBuilder<double>(
        valueListenable: scrollOffset,
        builder: (context, offset, _) {
          final vh = MediaQuery.sizeOf(context).height;
          final page = vh > 0
              ? (offset / vh).round().clamp(0, chapterCount - 1)
              : 0;

          return Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_R.full),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _S.md,
                    vertical: _S.xs + 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(_R.full),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Back
                      _NavButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onPressed: page > 0 ? onBack : null,
                        tp: tp,
                      ),
                      const SizedBox(width: _S.sm),
                      // Dots
                      Row(
                        children: List.generate(chapterCount, (i) {
                          final active = i == page;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: active ? 22 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: active
                                  ? tp.accent
                                  : Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(width: _S.sm),
                      // Next
                      _NavButton(
                        icon: Icons.arrow_forward_ios_rounded,
                        onPressed: page < chapterCount - 1 ? onNext : null,
                        tp: tp,
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
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final ThemeProvider tp;

  const _NavButton({
    required this.icon,
    required this.onPressed,
    required this.tp,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(_R.full),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 16,
            color: onPressed != null ? tp.accent : Colors.white24,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Chapter base — scroll-driven parallax + fade
// ═════════════════════════════════════════════════════════════════════════════

abstract class _ChapterBase extends StatelessWidget {
  final ValueNotifier<double> scrollOffset;
  final int chapterIndex;
  final ThemeProvider tp;

  const _ChapterBase({
    required this.scrollOffset,
    required this.chapterIndex,
    required this.tp,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: scrollOffset,
      builder: (context, offset, _) {
        final vh = MediaQuery.sizeOf(context).height;
        if (vh == 0) return const SizedBox.shrink();
        final local = offset - chapterIndex * vh;
        final progress = (local / vh).clamp(-1.0, 1.0);
        final vis = (1.0 - progress.abs()).clamp(0.0, 1.0);

        return Opacity(
          opacity: vis,
          child: Transform.translate(
            offset: Offset(0, progress * 60),
            child: buildChapter(context, progress, vis),
          ),
        );
      },
    );
  }

  Widget buildChapter(BuildContext context, double progress, double vis);
}

// ── Glass card helper ─────────────────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;

  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(_S.xl),
    this.borderRadius = _R.xl,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.06),
                Colors.white.withValues(alpha: 0.02),
              ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─ Pill label ────────────────────────────────────────────────────────────────
class _PillLabel extends StatelessWidget {
  final String text;
  final Color color;

  const _PillLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(_R.full),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Chapter 1 — Hero
// ═════════════════════════════════════════════════════════════════════════════

class _HeroChapter extends _ChapterBase {
  const _HeroChapter({
    required super.scrollOffset,
    required super.chapterIndex,
    required super.tp,
  });

  @override
  Widget buildChapter(BuildContext context, double progress, double vis) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _S.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PillLabel(text: 'CLOUD-POWERED STREAMING', color: tp.accentLight)
                .animate()
                .fadeIn(delay: 200.ms, duration: 600.ms)
                .slideY(begin: 0.2, end: 0, duration: 600.ms, curve: Curves.easeOutCubic),

            const SizedBox(height: _S.xl),

            Text(
              'Stream your games.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 46,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.5,
                height: 1.1,
              ),
              textAlign: TextAlign.center,
            )
                .animate()
                .fadeIn(delay: 380.ms, duration: 700.ms)
                .slideY(begin: 0.15, end: 0, duration: 700.ms, curve: Curves.easeOutCubic),

            const SizedBox(height: _S.sm),

            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [tp.accent, tp.accentLight],
              ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
              child: const Text(
                'Anywhere.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 46,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.5,
                  height: 1.1,
                ),
                textAlign: TextAlign.center,
              ),
            )
                .animate()
                .fadeIn(delay: 560.ms, duration: 700.ms)
                .slideY(begin: 0.15, end: 0, duration: 700.ms, curve: Curves.easeOutCubic)
                .shimmer(delay: 1200.ms, duration: 1800.ms),

            const SizedBox(height: _S.xl + 8),

            Text(
              'Play your entire PC library on any device\nwith near-zero latency.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 16,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            )
                .animate()
                .fadeIn(delay: 720.ms, duration: 600.ms),

            const SizedBox(height: _S.xxl),

            // Stat chips
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatChip(label: '< 5ms', sub: 'Latency', color: tp.accent),
                const SizedBox(width: _S.md),
                _StatChip(label: '4K', sub: 'HDR', color: tp.accentLight),
                const SizedBox(width: _S.md),
                _StatChip(label: 'AV1', sub: 'Codec', color: Colors.cyanAccent),
              ],
            )
                .animate()
                .fadeIn(delay: 900.ms, duration: 500.ms)
                .slideY(begin: 0.1, end: 0, duration: 500.ms),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String sub;
  final Color color;

  const _StatChip({required this.label, required this.sub, required this.color});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      borderRadius: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Chapter 2 — Latency
// ═════════════════════════════════════════════════════════════════════════════

class _LatencyChapter extends _ChapterBase {
  const _LatencyChapter({
    required super.scrollOffset,
    required super.chapterIndex,
    required super.tp,
  });

  @override
  Widget buildChapter(BuildContext context, double progress, double vis) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _S.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PillLabel(text: 'ZERO-LAG PIPELINE', color: tp.accent),
              const SizedBox(height: _S.xl),

              // Diagram: PC → Shield → Device
              _PipelineDiagram(tp: tp),
              const SizedBox(height: _S.xxl),

              _GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ultra Low Latency',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: _S.md),
                    Text(
                      'Hardware-accelerated encoding via AV1, HEVC and H.264 with WebRTC transport. Experience sub-5ms end-to-end.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: _S.lg),
                    _LatencyRow('Host Encode', '0.8 ms', tp.accentLight),
                    const SizedBox(height: _S.sm),
                    _LatencyRow('Network', '1.5 ms', Colors.cyanAccent),
                    const SizedBox(height: _S.sm),
                    _LatencyRow('Decode', '1.2 ms', tp.accentLight),
                    Divider(color: Colors.white.withValues(alpha: 0.08), height: 24),
                    _LatencyRow('Total', '3.5 ms', Colors.greenAccent, bold: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PipelineDiagram extends StatelessWidget {
  final ThemeProvider tp;
  const _PipelineDiagram({required this.tp});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _DiagramNode(icon: Icons.computer, label: 'PC', tp: tp),
        _DiagramLine(tp: tp),
        _DiagramNode(icon: Icons.security, label: 'Secure', tp: tp, accent: true),
        _DiagramLine(tp: tp),
        _DiagramNode(icon: Icons.devices, label: 'Any Device', tp: tp),
      ],
    );
  }
}

class _DiagramNode extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeProvider tp;
  final bool accent;

  const _DiagramNode({
    required this.icon,
    required this.label,
    required this.tp,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent ? tp.accent.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.06),
            border: Border.all(
              color: accent ? tp.accent.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Icon(
            icon,
            size: 24,
            color: accent ? tp.accentLight : Colors.white54,
          ),
        ).animate(onPlay: (c) => accent ? c.repeat(reverse: true) : null)
         .scale(
           begin: accent ? const Offset(1.0, 1.0) : const Offset(1.0, 1.0),
           end: accent ? const Offset(1.12, 1.12) : const Offset(1.0, 1.0),
           duration: 1800.ms,
         ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.45),
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _DiagramLine extends StatelessWidget {
  final ThemeProvider tp;
  const _DiagramLine({required this.tp});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 1,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.05),
            tp.accent.withValues(alpha: 0.6),
            Colors.white.withValues(alpha: 0.05),
          ],
        ),
      ),
    );
  }
}

class _LatencyRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool bold;

  const _LatencyRow(this.label, this.value, this.color, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: bold ? 0.85 : 0.55),
            fontSize: bold ? 14 : 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: bold ? 14 : 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Chapter 3 — Gamepad First
// ═════════════════════════════════════════════════════════════════════════════

class _GamepadChapter extends _ChapterBase {
  const _GamepadChapter({
    required super.scrollOffset,
    required super.chapterIndex,
    required super.tp,
  });

  @override
  Widget buildChapter(BuildContext context, double progress, double vis) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _S.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PillLabel(text: 'GAMEPAD-FIRST', color: Colors.purpleAccent.shade100),
              const SizedBox(height: _S.xl),

              Icon(
                Icons.gamepad_rounded,
                size: 64,
                color: tp.accentLight,
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scale(
                    begin: const Offset(0.9, 0.9),
                    end: const Offset(1.08, 1.08),
                    duration: 2.seconds,
                    curve: Curves.easeInOut,
                  ),

              const SizedBox(height: _S.xxl),

              _GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Built for the Couch',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: _S.md),
                    Text(
                      'Full spatial D-pad navigation. Every screen, every button — designed for physical controllers from day one.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: _S.lg),
                    _MappingRow('A / ✕', 'Select & Launch'),
                    const SizedBox(height: _S.sm),
                    _MappingRow('B / ◯', 'Back & Cancel'),
                    const SizedBox(height: _S.sm),
                    _MappingRow('X / ▢', 'Server Options'),
                    const SizedBox(height: _S.sm),
                    _MappingRow('Y / △', 'Toggle Favourite'),
                    const SizedBox(height: _S.sm),
                    _MappingRow('D-Pad', 'Navigate UI'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MappingRow extends StatelessWidget {
  final String button;
  final String action;

  const _MappingRow(this.button, this.action);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Text(
            button,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: _S.md),
        Text(
          action,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Chapter 4 — Cloud Sync
// ═════════════════════════════════════════════════════════════════════════════

class _CloudChapter extends _ChapterBase {
  final VoidCallback onGetStarted;

  const _CloudChapter({
    required super.scrollOffset,
    required super.chapterIndex,
    required super.tp,
    required this.onGetStarted,
  });

  @override
  Widget buildChapter(BuildContext context, double progress, double vis) {
    final vh = MediaQuery.sizeOf(context).height;
    final compactLayout = vh < 800;

    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PillLabel(text: 'CLOUD SYNC', color: Colors.greenAccent.shade200),
        SizedBox(height: compactLayout ? _S.md : _S.xl),

        // Pulsing cloud icon
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: compactLayout ? 72 : 90,
              height: compactLayout ? 72 : 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tp.accent.withValues(alpha: 0.08),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true))
             .scale(
               begin: const Offset(1.0, 1.0),
               end: const Offset(1.3, 1.3),
               duration: 2.seconds,
             )
             .fadeIn(duration: 1.seconds),
            Icon(
              Icons.cloud_done_rounded,
              size: compactLayout ? 42 : 52,
              color: tp.accentLight,
            ),
          ],
        ),

        SizedBox(height: compactLayout ? _S.lg : _S.xxl),

        _GlassCard(
          padding: EdgeInsets.all(compactLayout ? _S.md : _S.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'One account, every device.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compactLayout ? 22 : 26,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              SizedBox(height: compactLayout ? _S.sm : _S.md),
              Text(
                'Sign in with Jujo Cloud to automatically sync your server list, settings, and favourites across all your devices.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: compactLayout ? 13 : 14,
                  height: 1.6,
                ),
              ),
              SizedBox(height: compactLayout ? _S.md : _S.xl),

              // Feature list
              _CloudFeature(icon: Icons.sync_rounded, text: 'Server list sync', tp: tp),
              const SizedBox(height: _S.sm),
              _CloudFeature(icon: Icons.settings_rounded, text: 'Settings backup', tp: tp),
              const SizedBox(height: _S.sm),
              _CloudFeature(icon: Icons.favorite_rounded, text: 'Favourites everywhere', tp: tp),
              const SizedBox(height: _S.sm),
              _CloudFeature(icon: Icons.lock_rounded, text: 'End-to-end secured', tp: tp),
            ],
          ),
        ),

        SizedBox(height: compactLayout ? _S.md : _S.xl),

        // CTA
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onGetStarted,
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            label: const Text(
              'Get Started',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: tp.accent,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: compactLayout ? 14 : 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_R.lg),
              ),
              elevation: 0,
            ),
          ),
        )
            .animate()
            .fadeIn(duration: 500.ms)
            .scale(
              begin: const Offset(0.95, 0.95),
              end: const Offset(1.0, 1.0),
              duration: 500.ms,
              curve: Curves.easeOutBack,
            ),
      ],
    );

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: _S.xl, vertical: _S.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: content,
        ),
      ),
    );
  }
}

class _CloudFeature extends StatelessWidget {
  final IconData icon;
  final String text;
  final ThemeProvider tp;

  const _CloudFeature({required this.icon, required this.text, required this.tp});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: tp.accentLight),
        const SizedBox(width: _S.md),
        Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
