import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TourStep {
  const TourStep({
    required this.title,
    required this.desc,
    this.targetKey,
    this.spotRadius = 44.0,
    this.tooltipAbove = false,
  });

  final String title;
  final String desc;

  final GlobalKey? targetKey;

  final double spotRadius;

  final bool tooltipAbove;

  Rect? get _rect {
    final ctx = targetKey?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final offset = box.localToGlobal(Offset.zero);
    return offset & box.size;
  }

  Offset targetCenter(Size screen) {
    final r = _rect;
    if (r == null) return screen.center(Offset.zero);
    return r.center;
  }
}

class TourController extends ChangeNotifier {
  TourController._();
  static final instance = TourController._();

  List<TourStep> _steps = [];
  int _idx = 0;
  bool _active = false;

  bool get isActive => _active;
  int get currentIndex => _idx;
  int get total => _steps.length;
  TourStep? get current => _active && _steps.isNotEmpty ? _steps[_idx] : null;

  void start(List<TourStep> steps) {
    if (steps.isEmpty) return;
    _steps = steps;
    _idx = 0;
    _active = true;
    notifyListeners();
  }

  void next() {
    if (!_active) return;
    if (_idx < _steps.length - 1) {
      _idx++;
      notifyListeners();
    } else {
      dismiss();
    }
  }

  void dismiss() {
    _active = false;
    _steps = [];
    _idx = 0;
    notifyListeners();
  }
}

class TourOverlay extends StatefulWidget {
  const TourOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _posController;
  late final AnimationController _pulseController;

  Offset _currentSpot = Offset.zero;
  Offset _targetSpot = Offset.zero;
  late Animation<Offset> _spotAnim;
  bool _built = false;

  @override
  void initState() {
    super.initState();

    _posController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    _spotAnim = AlwaysStoppedAnimation(Offset.zero);
    TourController.instance.addListener(_onTourChanged);
  }

  @override
  void dispose() {
    TourController.instance.removeListener(_onTourChanged);
    _posController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _onTourChanged() {
    if (!mounted) return;
    setState(() {});
    final step = TourController.instance.current;
    if (step == null) return;
    final size = MediaQuery.sizeOf(context);
    final next = step.targetCenter(size);

    if (!_built) {
      _built = true;
      _currentSpot = next;
      _targetSpot = next;
      _spotAnim = AlwaysStoppedAnimation(next);
      return;
    }
    _currentSpot = _targetSpot;
    _targetSpot = next;
    _spotAnim = _posController.drive(
      Tween<Offset>(begin: _currentSpot, end: _targetSpot).chain(
        CurveTween(curve: Curves.easeInOutCubic),
      ),
    );
    _posController
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = TourController.instance;
    return Stack(
      children: [
        widget.child,
        if (ctrl.isActive) _buildTourLayer(context, ctrl),
      ],
    );
  }

  Widget _buildTourLayer(BuildContext context, TourController ctrl) {
    final step = ctrl.current!;
    final size = MediaQuery.sizeOf(context);
    final spotR = step.spotRadius;

    return AnimatedBuilder(
      animation: Listenable.merge([_posController, _pulseController]),
      builder: (ctx, _) {
        final spot = _spotAnim.value;
        final pulse = 1.0 + _pulseController.value * 0.18;

        final tipAbove = step.tooltipAbove ||
            spot.dy > size.height * 0.65;
        final tipY = tipAbove
            ? spot.dy - spotR * pulse - 160
            : spot.dy + spotR * pulse + 16;
        final tipX = (spot.dx - 140).clamp(12.0, size.width - 292.0);

        return FocusScope(
          autofocus: true,
          child: Focus(
          autofocus: true,
          onKeyEvent: (_, ev) {
            if (ev is! KeyDownEvent) return KeyEventResult.ignored;
            final k = ev.logicalKey;
            if (k == LogicalKeyboardKey.gameButtonA ||
                k == LogicalKeyboardKey.enter ||
                k == LogicalKeyboardKey.select) {
              ctrl.next();
              return KeyEventResult.handled;
            }
            if (k == LogicalKeyboardKey.gameButtonB ||
                k == LogicalKeyboardKey.gameButtonX ||
                k == LogicalKeyboardKey.escape ||
                k == LogicalKeyboardKey.goBack) {
              ctrl.dismiss();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: ctrl.next,
            child: SizedBox.expand(
              child: Stack(
                children: [

                  CustomPaint(
                    size: size,
                    painter: _SpotlightPainter(
                      center: spot,
                      radius: spotR * pulse,
                    ),
                  ),

                  Positioned(
                    left: spot.dx - spotR * pulse - 10,
                    top: spot.dy - spotR * pulse - 10,
                    child: IgnorePointer(
                      child: Container(
                        width: (spotR * pulse + 10) * 2,
                        height: (spotR * pulse + 10) * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(
                                alpha: 0.35 - _pulseController.value * 0.25),
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    left: tipX,
                    top: tipY.clamp(8.0, size.height - 200),
                    child: _TourTooltip(
                      step: step,
                      index: ctrl.currentIndex,
                      total: ctrl.total,
                      onNext: ctrl.next,
                      onSkip: ctrl.dismiss,
                    ),
                  ),

                  Positioned(
                    bottom: 32,
                    left: 0,
                    right: 0,
                    child: _StepDots(
                      total: ctrl.total,
                      current: ctrl.currentIndex,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        );
      },
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.center, required this.radius});

  final Offset center;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.72);

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.center != center || old.radius != radius;
}

class _TourTooltip extends StatelessWidget {
  const _TourTooltip({
    required this.step,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onSkip,
  });

  final TourStep step;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final isLast = index == total - 1;
    return SizedBox(
      width: 284,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [

              Text(
                '${index + 1} / $total',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),

              Text(
                step.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                step.desc,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: onSkip,
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: onNext,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        isLast ? 'Done' : 'Next  →',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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

class _StepDots extends StatelessWidget {
  const _StepDots({required this.total, required this.current});

  final int total;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active
                ? Colors.white
                : Colors.white.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
