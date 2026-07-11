import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'cinematic_audio.dart';

class CinematicIntroScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final bool reducedMotion;
  const CinematicIntroScreen({
    required this.onComplete,
    this.reducedMotion = false,
    super.key,
  });

  @override
  State<CinematicIntroScreen> createState() => _CinematicIntroScreenState();
}

class _CinematicIntroScreenState extends State<CinematicIntroScreen>
    with TickerProviderStateMixin {
  static const _cyan = Color(0xFF22D3EE);
  static const _rose = Color(0xFFF43F5E);

  late final AnimationController _fallController;
  late final AnimationController _explosionController;
  late final AnimationController _logoRevealController;
  late final AnimationController _continueController;
  late final AnimationController _particleController;
  late final AnimationController _bounceController;

  late final Animation<double> _progress;
  late final Animation<double> _explosionProgress;
  late final Animation<double> _bounceTranslateY;
  late final Animation<double> _bounceRotation;

  Timer? _bounceTimer;
  final FocusNode _focusNode = FocusNode();

  final CinematicAudio _audio = CinematicAudio();
  final List<_Particle> _particles = [];
  final List<_AmbientParticle> _ambientParticles = [];
  final List<_WindLine> _windLines = [];

  bool _impactTriggered = false;
  bool _showContinue = false;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();

    // Fall animation: 4.5s
    _fallController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    );
    _progress = CurvedAnimation(parent: _fallController, curve: Curves.linear);

    // Explosion animation: 0.8s
    _explosionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _explosionProgress = CurvedAnimation(
      parent: _explosionController,
      curve: Curves.easeOut,
    );

    // Logo reveal animation: icon pops out of the blast, then text
    // slides out from behind it. Raw controller value is shaped with
    // per-phase curves inside _buildLogo.
    _logoRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // Continue text pulse
    _continueController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Ambient particle drift: very slow, continuous
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );

    // Cube bounce+wobble: matches JujoBrandTitle animation
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2250),
    );
    _bounceTranslateY = _bounceSequence(const [
      0,
      -20,
      2,
      -9,
      1,
      0,
    ]).animate(_bounceController);
    _bounceRotation = _bounceSequence(const [
      0,
      21,
      -11,
      7,
      -3,
      0,
    ]).animate(_bounceController);

    // Generate 60 explosion particles
    final rng = math.Random(42);
    for (int i = 0; i < 60; i++) {
      final angle = rng.nextDouble() * 2 * math.pi;
      final speed = 80.0 + rng.nextDouble() * 250.0;
      _particles.add(
        _Particle(
          angle: angle,
          speed: speed,
          size: 2.0 + rng.nextDouble() * 5.0,
          color: rng.nextBool() ? _cyan : Colors.white,
        ),
      );
    }

    // Generate 40 ambient background particles
    for (int i = 0; i < 40; i++) {
      _ambientParticles.add(
        _AmbientParticle(
          baseX: rng.nextDouble(),
          baseY: rng.nextDouble(),
          driftSpeed: 0.3 + rng.nextDouble() * 0.7,
          driftPhase: rng.nextDouble() * 2 * math.pi,
          size: 0.8 + rng.nextDouble() * 1.8,
          baseOpacity: 0.03 + rng.nextDouble() * 0.08,
          color: rng.nextBool() ? _cyan : Colors.white,
        ),
      );
    }

    // Generate 40 wind lines (varied speeds, positions, lengths)
    for (int i = 0; i < 40; i++) {
      _windLines.add(
        _WindLine(
          x: rng.nextDouble(),
          speedMultiplier: 0.5 + rng.nextDouble() * 1.0,
          length: 30.0 + rng.nextDouble() * 170.0,
          opacity: 0.05 + rng.nextDouble() * 0.15,
          width: 0.5 + rng.nextDouble() * 1.2,
        ),
      );
    }

    // Listen for impact
    _fallController.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_impactTriggered) {
        _triggerImpact();
      }
    });

    if (widget.reducedMotion) {
      _impactTriggered = true;
      _showContinue = true;
      _fallController.value = 1;
      _explosionController.value = 1;
      _logoRevealController.value = 1;
    } else {
      _continueController.repeat(reverse: true);
      _particleController.repeat();
      _initAudio();
      _fallController.forward();
    }

    // autofocus is skipped when the scope already has focus — force it so
    // gamepad/keyboard can dismiss (see gamepad focus-trap notes).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _initAudio() async {
    try {
      await _audio.initialize();
      _audio.playFall();
    } catch (e) {
      debugPrint('CinematicAudio init error: $e');
    }
  }

  void _triggerImpact() {
    _impactTriggered = true;
    _explosionController.forward();
    _audio.playImpact();

    // Logo emerges in sync with the blast — the flash covers the
    // falling-icon -> logo-icon swap.
    _logoRevealController.forward();

    Future.delayed(const Duration(milliseconds: 150), () {
      _audio.playRevealChime();
    });

    // Start cube bounce after logo reveal completes (900ms reveal)
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      _bounceController.forward();
      _bounceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) _bounceController.forward(from: 0);
      });
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showContinue = true);
    });
  }

  void _handleDismiss() {
    if (_dismissing) return;
    if (_showContinue) {
      _dismissing = true;
      _audio.dispose();
      widget.onComplete();
    } else if (_fallController.isAnimating) {
      _fallController.stop(canceled: false);
      if (!_impactTriggered) _triggerImpact();
    }
  }

  @override
  void dispose() {
    _bounceTimer?.cancel();
    _focusNode.dispose();
    _audio.dispose();
    _fallController.dispose();
    _explosionController.dispose();
    _logoRevealController.dispose();
    _continueController.dispose();
    _particleController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  /// TweenSequence matching JujoBrandTitle's bounce+wobble keyframes.
  static const _bounceCurve = Cubic(0.25, 0.8, 0.25, 1);

  static TweenSequence<double> _bounceSequence(List<double> keyframes) {
    return TweenSequence<double>([
      for (var i = 0; i < keyframes.length - 1; i++)
        TweenSequenceItem(
          tween: Tween(
            begin: keyframes[i],
            end: keyframes[i + 1],
          ).chain(CurveTween(curve: _bounceCurve)),
          weight: 1,
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          _handleDismiss();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF040208),
        body: GestureDetector(
          onTap: _handleDismiss,
          onTapDown: (_) => _handleDismiss(),
          child: ListenableBuilder(
            listenable: Listenable.merge([
              _fallController,
              _explosionController,
              _logoRevealController,
            ]),
            builder: (context, _) {
              final p = _progress.value;

              // ── Hang-time physics ──
              // Phase 1 (0-0.30): Icon falls to visible mid-upper position (~35% screen)
              // Phase 2 (0.30-0.60): Icon HANGS — barely moves, wind intensifies
              // Phase 3 (0.60-1.0): Rapid acceleration to impact
              double fallFraction;
              if (p < 0.30) {
                // Phase 1: normal fall to hang position
                final phase1 = p / 0.30;
                fallFraction = phase1 * phase1 * 0.55;
              } else if (p < 0.60) {
                // Phase 2: hang time — icon barely moves (55% -> 57%)
                final phase2 = (p - 0.30) / 0.30;
                fallFraction = 0.55 + phase2 * 0.02;
              } else {
                // Phase 3: rapid acceleration (57% -> 100%)
                final phase3 = (p - 0.60) / 0.40;
                final fast = phase3 * phase3 * phase3;
                fallFraction = 0.57 + fast * 0.43;
              }

              // ── Deformation: builds with velocity ──
              double deformFactor = 0.0;
              if (p < 0.30) {
                // Phase 1: subtle stretch during fall
                final phase1 = p / 0.30;
                deformFactor = phase1 * 0.3;
              } else if (p < 0.60) {
                // Phase 2: minimal during hang
                deformFactor = 0.1;
              } else {
                // Phase 3: intense stretch during acceleration
                final phase3 = (p - 0.60) / 0.40;
                deformFactor = 0.1 + phase3 * phase3 * 0.9;
              }

              // Icon physics: falls from top, lands with bottom edge at impact
              final startY = -150.0;
              final endY = size.height * 0.55 - 80;
              final iconY = startY + (endY - startY) * fallFraction;
              final iconCenterX = size.width / 2;
              final impactY = size.height * 0.55;

              // Wind intensity: builds during hang, peaks at impact
              double windIntensity;
              if (p < 0.33) {
                windIntensity = (p / 0.33) * 0.4;
              } else if (p < 0.67) {
                // Hang phase: wind intensifies while icon is still
                final hangP = (p - 0.33) / 0.34;
                windIntensity = 0.4 + hangP * 0.6;
              } else {
                windIntensity = 1.0;
              }

              // Camera shake: short, decaying jolt right after impact.
              double shakeX = 0, shakeY = 0;
              if (_impactTriggered && _explosionProgress.value < 0.45) {
                final damp = 1.0 - _explosionProgress.value / 0.45;
                final phase = _explosionProgress.value * 60;
                shakeX = math.sin(phase * 1.3) * 7 * damp;
                shakeY = math.cos(phase) * 9 * damp;
              }

              return Transform.translate(
                offset: Offset(shakeX, shakeY),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildBackground(p, impactY),
                    _buildAmbientParticles(),
                    if (!_impactTriggered) _buildWindLines(p, windIntensity),
                    _buildLaserLine(p, impactY),
                    if (!_impactTriggered || _explosionProgress.value < 0.2)
                      _buildFallingIcon(iconY, deformFactor),
                    if (_impactTriggered) _buildExplosion(iconCenterX, impactY),
                    if (_impactTriggered) _buildLogo(size, impactY),
                    if (_showContinue) _buildContinuePrompt(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Background ─────────────────────────────────────────────

  Widget _buildBackground(double p, double impactY) {
    // Horizon glow ramps up as the box approaches the surface.
    final approach = Curves.easeIn.transform(p.clamp(0.0, 1.0));
    final glowAlpha = 0.03 + approach * 0.10;

    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.9,
          colors: [
            Color(0xFF040208), // deep center
            Color(0xFF080818), // subtle purple
            Color(0xFF0A0A20), // outer edge
          ],
        ),
      ),
      child: Stack(
        children: [
          // Subtle cyan nebula top-left
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [_cyan.withValues(alpha: 0.04), Colors.transparent],
                ),
              ),
            ),
          ),
          // Subtle purple nebula bottom-right
          Positioned(
            bottom: -60,
            right: -60,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF8B5CF6).withValues(alpha: 0.03),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Horizon glow band centered on the impact surface
          Positioned(
            top: impactY - 110,
            left: 0,
            right: 0,
            height: 220,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      _cyan.withValues(alpha: glowAlpha),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // Below-surface depth: solid darker floor under the impact line
          Positioned(
            top: impactY,
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(
                        0xFF06121A,
                      ).withValues(alpha: 0.0 + approach * 0.5),
                      Colors.black.withValues(alpha: 0.25 + approach * 0.45),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Vignette: keeps the eye on the action, reads cinematic
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.2,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.45),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Ambient Particles ───────────────────────────────────────

  Widget _buildAmbientParticles() {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _particleController,
        builder: (context, _) {
          return CustomPaint(
            size: Size.infinite,
            painter: _AmbientParticlesPainter(
              particles: _ambientParticles,
              time: _particleController.value * 20,
            ),
          );
        },
      ),
    );
  }

  // ── Wind Lines ────────────────────────────────────────────

  Widget _buildWindLines(double p, double intensity) {
    if (intensity < 0.01) return const SizedBox.shrink();
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _WindLinePainter(
          windLines: _windLines,
          progress: p,
          intensity: intensity,
        ),
      ),
    );
  }

  // ── Laser Surface Line ─────────────────────────────────────

  Widget _buildLaserLine(double p, double impactY) {
    if (p < 0.75) return const SizedBox.shrink();

    final localP = ((p - 0.75) / 0.25).clamp(0.0, 1.0);
    final drawProgress = 1.0 - math.pow(1.0 - localP, 3);
    final halfWidth = 110.0 * drawProgress;

    double rippleTime = 0.0;
    double bendY = 0.0;
    double opacity = 1.0;

    if (_impactTriggered) {
      rippleTime = _explosionProgress.value * 0.8;
      bendY = 45.0 * math.sin(rippleTime * 0.15) * math.exp(-rippleTime * 0.05);
      opacity = (1.0 - (rippleTime / 0.5)).clamp(0.0, 1.0);
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _LaserLinePainter(
            centerY: impactY,
            halfWidth: halfWidth,
            bendY: bendY,
            opacity: opacity,
          ),
        ),
      ),
    );
  }

  // ── Falling Icon ─────────────────────────────────────────────

  Widget _buildFallingIcon(double y, double deformFactor) {
    final squashX = 1.0 - deformFactor * 0.2;
    final stretchY = 1.0 + deformFactor * 0.6;

    double iconOpacity = 1.0;
    if (_impactTriggered) {
      iconOpacity = (1.0 - _explosionProgress.value * 2.0).clamp(0.0, 1.0);
    }

    return Positioned(
      left: 0,
      right: 0,
      top: y,
      child: Opacity(
        opacity: iconOpacity,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(squashX, stretchY, 1.0),
          child: Center(
            child: CustomPaint(
              size: const Size(80, 80),
              painter: const _JujoBoxPainter(_rose),
            ),
          ),
        ),
      ),
    );
  }

  // ── Explosion ────────────────────────────────────────────────

  Widget _buildExplosion(double centerX, double centerY) {
    return Positioned.fill(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ExplosionPainter(
          particles: _particles,
          progress: _explosionProgress.value,
          centerX: centerX,
          centerY: centerY,
        ),
      ),
    );
  }

  // ── Logo Reveal ──────────────────────────────────────────────

  Widget _buildLogo(Size size, double impactY) {
    final textScale = math.min(size.width / 600, 1.2);
    final iconSize = 48 * textScale;
    final gap = 10 * textScale;

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: Listenable.merge([_logoRevealController, _bounceController]),
        builder: (context, _) {
          final t = _logoRevealController.value;
          // Phase 1: the cube pops out of the blast with overshoot —
          // it was "inside" the falling box and the crash frees it.
          final iconT = Curves.easeOutBack.transform(
            (t / 0.45).clamp(0.0, 1.0),
          );
          // Phase 2: the wordmark slides out from behind the cube.
          final textT = Curves.easeOutCubic.transform(
            ((t - 0.30) / 0.70).clamp(0.0, 1.0),
          );

          final textStyle = TextStyle(
            color: Colors.white,
            fontSize: 48 * textScale,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          );
          final textPainter = TextPainter(
            text: TextSpan(
              text: 'JUJO',
              style: textStyle,
              children: const [
                TextSpan(
                  text: '.Stream',
                  style: TextStyle(color: _cyan),
                ),
              ],
            ),
            textDirection: TextDirection.ltr,
          )..layout();

          final textWidth = textPainter.width + 4;
          final revealTextWidth = textWidth * textT;
          final rowHeight = math.max(iconSize, textPainter.height);
          final iconScale = iconSize / 48;

          // Row is centered horizontally; at t=0 it is just the cube, so
          // the cube sits exactly on the explosion center and the whole
          // composition re-centers as the text grows.
          return Align(
            alignment: Alignment.topCenter,
            child: Transform.translate(
              offset: Offset(0, impactY - rowHeight / 2),
              child: SizedBox(
                height: rowHeight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Transform.scale(
                      scale: iconT,
                      child: Transform.translate(
                        offset: Offset(0, _bounceTranslateY.value * iconScale),
                        child: Transform.rotate(
                          angle: _bounceRotation.value * math.pi / 180,
                          child: CustomPaint(
                            size: Size.square(iconSize),
                            painter: const _JujoBoxPainter(_rose),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: gap * textT),
                    SizedBox(
                      width: revealTextWidth,
                      height: textPainter.height,
                      child: ClipRect(
                        child: OverflowBox(
                          maxWidth: textWidth,
                          alignment: Alignment.centerLeft,
                          child: Text.rich(
                            TextSpan(
                              text: 'JUJO',
                              style: textStyle,
                              children: const [
                                TextSpan(
                                  text: '.Stream',
                                  style: TextStyle(color: _cyan),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.visible,
                            softWrap: false,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Continue Prompt ──────────────────────────────────────────

  Widget _buildContinuePrompt() {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Positioned(
      bottom: bottomPad + 48,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _continueController,
          builder: (context, _) => Opacity(
            opacity: 0.4 + 0.6 * _continueController.value,
            child: Text(
              'Press any button to continue',
              style: const TextStyle(
                color: Color(0xFF22D3EE),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.0,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Data classes ─────────────────────────────────────────────

class _Particle {
  final double angle;
  final double speed;
  final double size;
  final Color color;
  _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
  });
}

class _AmbientParticle {
  final double baseX;
  final double baseY;
  final double driftSpeed;
  final double driftPhase;
  final double size;
  final double baseOpacity;
  final Color color;
  _AmbientParticle({
    required this.baseX,
    required this.baseY,
    required this.driftSpeed,
    required this.driftPhase,
    required this.size,
    required this.baseOpacity,
    required this.color,
  });
}

class _WindLine {
  final double x;
  final double speedMultiplier;
  final double length;
  final double opacity;
  final double width;
  _WindLine({
    required this.x,
    required this.speedMultiplier,
    required this.length,
    required this.opacity,
    required this.width,
  });
}

// ── Painters ─────────────────────────────────────────────────

class _LaserLinePainter extends CustomPainter {
  final double centerY;
  final double halfWidth;
  final double bendY;
  final double opacity;

  _LaserLinePainter({
    required this.centerY,
    required this.halfWidth,
    required this.bendY,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (halfWidth <= 0 || opacity <= 0) return;

    final cx = size.width / 2;
    final cy = centerY;

    // Draw line with gradient
    final linePath = Path();
    final segments = 40;
    for (int i = 0; i <= segments; i++) {
      final t = i / segments;
      final x = cx - halfWidth + t * halfWidth * 2;
      final wave = bendY * math.sin(t * math.pi);
      final y = cy + wave;
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }

    final lineRect = Rect.fromLTWH(cx - halfWidth, cy - 1, halfWidth * 2, 2);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          const Color(0xFF22D3EE).withValues(alpha: 0),
          const Color(0xFF22D3EE).withValues(alpha: opacity * 0.6),
          const Color(0xFFFFFFFF).withValues(alpha: opacity),
          const Color(0xFFFFFFFF).withValues(alpha: opacity),
          const Color(0xFF22D3EE).withValues(alpha: opacity * 0.6),
          const Color(0xFF22D3EE).withValues(alpha: 0),
        ],
        stops: const [0.0, 0.3, 0.45, 0.55, 0.7, 1.0],
      ).createShader(lineRect)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    canvas.drawPath(linePath, paint);

    // Glow effect
    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              const Color(0xFFFFFFFF).withValues(alpha: opacity * 0.25),
              const Color(0xFFFFFFFF).withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCenter(
              center: Offset(cx, cy + bendY * 0.5),
              width: 60,
              height: 60,
            ),
          );
    canvas.drawCircle(Offset(cx, cy + bendY * 0.5), 30, glowPaint);
  }

  @override
  bool shouldRepaint(_LaserLinePainter oldDelegate) =>
      oldDelegate.halfWidth != halfWidth ||
      oldDelegate.bendY != bendY ||
      oldDelegate.opacity != opacity;
}

class _ExplosionPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final double centerX;
  final double centerY;

  _ExplosionPainter({
    required this.particles,
    required this.progress,
    required this.centerX,
    required this.centerY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    // White flash at the moment of impact — covers the box -> logo swap.
    if (progress < 0.18) {
      final flashAlpha = (1.0 - progress / 0.18) * 0.5;
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: flashAlpha),
      );
    }

    // Expanding shockwave ring
    final ringT = Curves.easeOutCubic.transform(progress);
    final ringRadius = 20.0 + ringT * 300.0;
    final ringAlpha = (1.0 - progress) * 0.55;
    if (ringAlpha > 0.01) {
      canvas.drawCircle(
        Offset(centerX, centerY),
        ringRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 + 3.0 * (1.0 - progress)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
          ..color = const Color(0xFF22D3EE).withValues(alpha: ringAlpha),
      );
      // Inner hot ring, slightly behind the cyan one
      canvas.drawCircle(
        Offset(centerX, centerY),
        ringRadius * 0.7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 + 2.0 * (1.0 - progress)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
          ..color = Colors.white.withValues(alpha: ringAlpha * 0.6),
      );
    }

    for (final particle in particles) {
      final distance = particle.speed * progress;
      final x = centerX + math.cos(particle.angle) * distance;
      final y = centerY + math.sin(particle.angle) * distance;
      final opacity = (1.0 - progress).clamp(0.0, 1.0);
      final size = particle.size * (1.0 - progress * 0.5);

      final paint = Paint()
        ..color = particle.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, y), size, paint);
    }
  }

  @override
  bool shouldRepaint(_ExplosionPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _AmbientParticlesPainter extends CustomPainter {
  final List<_AmbientParticle> particles;
  final double time;

  _AmbientParticlesPainter({required this.particles, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final x =
          (particle.baseX * size.width) +
          math.sin(time * particle.driftSpeed + particle.driftPhase) * 6;
      final y =
          (particle.baseY * size.height) +
          math.cos(time * particle.driftSpeed * 0.6 + particle.driftPhase) * 4;
      final alpha =
          particle.baseOpacity *
          (0.6 + 0.4 * math.sin(time * 0.3 + particle.driftPhase));

      if (alpha < 0.01) continue;

      final paint = Paint()
        ..color = particle.color.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, y), particle.size, paint);
    }
  }

  @override
  bool shouldRepaint(_AmbientParticlesPainter oldDelegate) =>
      oldDelegate.time != time;
}

class _WindLinePainter extends CustomPainter {
  static const _color = Color(0xFF22D3EE);
  final List<_WindLine> windLines;
  final double progress;
  final double intensity;

  _WindLinePainter({
    required this.windLines,
    required this.progress,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity < 0.01) return;

    for (final line in windLines) {
      final x = line.x * size.width;
      final speed = line.speedMultiplier * (0.5 + intensity);
      // Lines stretch with speed — reads as motion blur.
      final length = line.length * (1.0 + intensity * 1.2);
      final cycle = size.height + length;

      // The camera falls WITH the icon, so the world streaks UPWARD past
      // it — scroll subtracts so lines travel bottom -> top.
      final scrollOffset = progress * size.height * 3.0 * speed;
      final baseY =
          (line.x * size.height * 7 +
              line.speedMultiplier * size.height -
              scrollOffset) %
          cycle;
      final y = baseY - length;

      final alpha = line.opacity * intensity;
      if (alpha < 0.01) continue;

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _color.withValues(alpha: 0),
            _color.withValues(alpha: alpha),
            _color.withValues(alpha: alpha),
            _color.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.2, 0.8, 1.0],
        ).createShader(Rect.fromLTWH(x - line.width / 2, y, line.width, length))
        ..strokeWidth = line.width
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(x, y), Offset(x, y + length), paint);
    }
  }

  @override
  bool shouldRepaint(_WindLinePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.intensity != intensity;
}

class _JujoBoxPainter extends CustomPainter {
  const _JujoBoxPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 48;

    final cube = Path()
      ..moveTo(41 * s, 14 * s)
      ..lineTo(24 * s, 4 * s)
      ..lineTo(7 * s, 14 * s)
      ..lineTo(7 * s, 34 * s)
      ..lineTo(24 * s, 44 * s)
      ..lineTo(41 * s, 34 * s)
      ..close();

    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * s
      ..strokeJoin = StrokeJoin.round;

    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawPath(cube, fill);
    canvas.drawPath(cube, stroke);

    final innerLines = Path()
      ..moveTo(16 * s, 18.998 * s)
      ..lineTo(23.993 * s, 24 * s)
      ..lineTo(31.995 * s, 18.998 * s)
      ..moveTo(24 * s, 24 * s)
      ..lineTo(24 * s, 33 * s);
    final clear = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(innerLines, clear);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_JujoBoxPainter oldDelegate) => oldDelegate.color != color;
}
