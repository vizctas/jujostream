import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/stream_configuration.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';

Color _fg(ThemeProvider tp) => tp.colors.isLight ? Colors.black87 : Colors.white;
Color _fgMid(ThemeProvider tp) => tp.colors.isLight ? Colors.black54 : Colors.white70;
Color _fgMuted(ThemeProvider tp) => tp.colors.isLight ? Colors.black38 : Colors.white54;

/// In-app controller layout editor. Tap a button to select it, then press a
/// physical gamepad key to remap that position. Tap again to cancel.
class ControllerLayoutEditor extends StatefulWidget {
  const ControllerLayoutEditor({super.key});

  @override
  State<ControllerLayoutEditor> createState() => _ControllerLayoutEditorState();
}

class _ControllerLayoutEditorState extends State<ControllerLayoutEditor> {
  static const int _A = 0x1000;
  static const int _B = 0x2000;
  static const int _X = 0x4000;
  static const int _Y = 0x8000;
  static const int _LB = 0x0100;
  static const int _RB = 0x0200;
  static const int _LS = 0x0040;
  static const int _RS = 0x0080;
  static const int _START = 0x0010;
  static const int _SELECT = 0x0020;
  static const int _UP = 0x0001;
  static const int _DOWN = 0x0002;
  static const int _LEFT = 0x0004;
  static const int _RIGHT = 0x0008;

  static const _buttons = <int, String>{
    _A: 'A', _B: 'B', _X: 'X', _Y: 'Y',
    _LB: 'LB', _RB: 'RB',
    _LS: 'L3', _RS: 'R3',
    _START: 'Start', _SELECT: 'Select',
    _UP: 'Up', _DOWN: 'Down', _LEFT: 'Left', _RIGHT: 'Right',
  };

  // Physical gamepad key â†’ moonlight flag
  static final Map<LogicalKeyboardKey, int> _hwToFlag = {
    LogicalKeyboardKey.gameButtonA: _A,
    LogicalKeyboardKey.gameButtonB: _B,
    LogicalKeyboardKey.gameButtonX: _X,
    LogicalKeyboardKey.gameButtonY: _Y,
    LogicalKeyboardKey.gameButtonLeft1: _LB,
    LogicalKeyboardKey.gameButtonRight1: _RB,
    LogicalKeyboardKey.gameButtonStart: _START,
    LogicalKeyboardKey.gameButtonSelect: _SELECT,
    LogicalKeyboardKey.arrowUp: _UP,
    LogicalKeyboardKey.arrowDown: _DOWN,
    LogicalKeyboardKey.arrowLeft: _LEFT,
    LogicalKeyboardKey.arrowRight: _RIGHT,
  };

  late Map<int, int> _remap;
  int? _listeningFor;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final c = context.read<SettingsProvider>().config;
    _remap = Map.of(c.customRemapTable);
  }

  @override
  void dispose() {
    if (_listeningFor != null) HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    super.dispose();
  }

  int _resolve(int flag) => _remap[flag] ?? flag;
  String _label(int flag) => _buttons[_resolve(flag)] ?? '?';

  void _onTap(int flag) {
    if (_listeningFor == flag) {
      // Cancel listen mode
      HardwareKeyboard.instance.removeHandler(_onHardwareKey);
      setState(() => _listeningFor = null);
      return;
    }
    if (_listeningFor != null) {
      HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    }
    setState(() => _listeningFor = flag);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  bool _onHardwareKey(KeyEvent event) {
    final target = _listeningFor;
    if (target == null) return false;
    if (event is! KeyDownEvent) return true; // consume while listening
    final physFlag = _hwToFlag[event.logicalKey];
    if (physFlag == null) return true; // consume unknown keys during listen
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    setState(() {
      if (physFlag == target) {
        _remap.remove(target); // identity â†’ clear mapping
      } else {
        _remap[target] = physFlag;
      }
      _listeningFor = null;
      _dirty = true;
    });
    return true;
  }

  void _save() {
    final settings = context.read<SettingsProvider>();
    settings.updateConfig(settings.config.copyWith(
      buttonRemapProfile: ButtonRemapProfile.custom,
      customRemapTable: Map.unmodifiable(_remap),
    ));
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Layout saved'), duration: Duration(seconds: 1)),
    );
  }

  void _reset() {
    if (_listeningFor != null) {
      HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    }
    setState(() {
      _remap.clear();
      _listeningFor = null;
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final accent = tp.accent;

    return Scaffold(
      backgroundColor: tp.surface,
      appBar: AppBar(
        title: Text('Controller Layout', style: TextStyle(color: _fg(tp), fontSize: 17, fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: _fgMid(tp)),
        actions: [
          if (_dirty)
            TextButton.icon(
              onPressed: _save,
              icon: Icon(Icons.save_rounded, size: 17, color: accent),
              label: Text('Save', style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
            ),
          IconButton(
            icon: Icon(Icons.restart_alt_rounded, color: _fgMuted(tp)),
            tooltip: 'Reset to defaults',
            onPressed: _reset,
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (ctx, box) {
          final layoutW = box.maxWidth > box.maxHeight
              ? box.maxWidth * 0.82
              : box.maxWidth * 0.94;
          final layoutH = box.maxWidth > box.maxHeight
              ? box.maxHeight * 0.82
              : box.maxWidth * 0.68;
          return Column(
            children: [
              _buildHintBanner(tp, accent),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: layoutW,
                    height: layoutH,
                    child: _buildLayout(layoutW, layoutH, accent, tp),
                  ),
                ),
              ),
              _buildLegend(tp, accent),
              const SizedBox(height: 12),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildHintBanner(ThemeProvider tp, Color accent) {
    if (_listeningFor != null) {
      final sel = _buttons[_listeningFor!] ?? '?';
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        color: const Color(0xFFFF4081).withValues(alpha: 0.12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.gamepad_outlined, size: 16, color: Color(0xFFFF4081)),
            const SizedBox(width: 7),
            Text(
              'Press a physical button to remap "$sel"  â€¢  Tap again to cancel',
              style: const TextStyle(
                color: Color(0xFFFF4081),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Text(
        'Tap a button, then press its new physical key on your gamepad',
        textAlign: TextAlign.center,
        style: TextStyle(color: _fgMuted(tp), fontSize: 13),
      ),
    );
  }

  Widget _buildLegend(ThemeProvider tp, Color accent) {
    final swaps = <String>[];
    for (final e in _remap.entries) {
      final from = _buttons[e.key] ?? '?';
      final to = _buttons[e.value] ?? '?';
      if (from != to) swaps.add('$from â†’ $to');
    }
    if (swaps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text('Default layout', style: TextStyle(color: _fgMuted(tp), fontSize: 13)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: swaps.map((s) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.28)),
          ),
          child: Text(
            s,
            style: TextStyle(color: _fgMid(tp), fontSize: 11, fontWeight: FontWeight.w500),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildLayout(double w, double h, Color accent, ThemeProvider tp) {
    final positions = <int, Offset>{
      _A: const Offset(0.78, 0.55),
      _B: const Offset(0.85, 0.40),
      _X: const Offset(0.71, 0.40),
      _Y: const Offset(0.78, 0.25),
      _UP: const Offset(0.22, 0.25),
      _DOWN: const Offset(0.22, 0.55),
      _LEFT: const Offset(0.15, 0.40),
      _RIGHT: const Offset(0.29, 0.40),
      _LB: const Offset(0.18, 0.05),
      _RB: const Offset(0.82, 0.05),
      _LS: const Offset(0.32, 0.70),
      _RS: const Offset(0.68, 0.70),
      _START: const Offset(0.58, 0.30),
      _SELECT: const Offset(0.42, 0.30),
    };

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: _ControllerOutlinePainter(tp.surfaceVariant)),
        ),
        for (final entry in positions.entries)
          _buildButtonNode(
            entry.key,
            entry.value.dx * w,
            entry.value.dy * h,
            accent,
            tp,
          ),
      ],
    );
  }

  Widget _buildButtonNode(int flag, double x, double y, Color accent, ThemeProvider tp) {
    final isListening = _listeningFor == flag;
    final isRemapped = _remap.containsKey(flag);
    const sz = 50.0;

    // Colors
    final bgColor = isListening
        ? const Color(0xFFFF4081).withValues(alpha: 0.22)
        : isRemapped
            ? accent.withValues(alpha: 0.18)
            : tp.background.withValues(alpha: 0.75);

    final borderColor = isListening
        ? const Color(0xFFFF4081)
        : isRemapped
            ? accent
            : tp.surfaceVariant.withValues(alpha: 0.6);

    final labelColor = isListening
        ? const Color(0xFFFF4081)
        : isRemapped
            ? accent
            : _fgMid(tp);

    return Positioned(
      left: x - sz / 2,
      top: y - sz / 2,
      child: GestureDetector(
        onTap: () => _onTap(flag),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: sz,
          height: sz,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor,
            border: Border.all(color: borderColor, width: isListening ? 2.0 : 1.4),
            boxShadow: isListening
                ? [BoxShadow(color: const Color(0xFFFF4081).withValues(alpha: 0.4), blurRadius: 14)]
                : isRemapped
                    ? [BoxShadow(color: accent.withValues(alpha: 0.22), blurRadius: 8)]
                    : null,
          ),
          alignment: Alignment.center,
          child: Text(
            _label(flag),
            style: TextStyle(
              color: labelColor,
              fontSize: 11,
              fontWeight: isListening || isRemapped ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _ControllerOutlinePainter extends CustomPainter {
  final Color lineColor;
  _ControllerOutlinePainter(this.lineColor);

  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = lineColor.withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s.width * 0.12, s.height * 0.10, s.width * 0.76, s.height * 0.55),
        const Radius.circular(28),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s.width * 0.14, s.height * 0.50, s.width * 0.18, s.height * 0.40),
        const Radius.circular(18),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s.width * 0.68, s.height * 0.50, s.width * 0.18, s.height * 0.40),
        const Radius.circular(18),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ControllerOutlinePainter old) => old.lineColor != lineColor;
}
