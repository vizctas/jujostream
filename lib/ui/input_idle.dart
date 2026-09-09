import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// App-wide "has the user touched anything lately?" signal.
///
/// Fed by hardware keys (remote / gamepad DPAD arrive as key events), pointer
/// events, and the native gamepad channel via [poke]. Flips to idle after
/// [timeout] without input and back the moment anything arrives.
class InputIdle {
  InputIdle._();

  static final InputIdle instance = InputIdle._();
  static const timeout = Duration(seconds: 3);

  final ValueNotifier<bool> idle = ValueNotifier<bool>(false);
  Timer? _timer;
  bool _installed = false;

  void ensureInstalled() {
    if (_installed) return;
    _installed = true;
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    poke();
  }

  bool _onKey(KeyEvent _) {
    poke();
    return false;
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent || event is PointerMoveEvent) poke();
  }

  /// Mark input activity: hints become visible and the idle timer restarts.
  void poke() {
    if (idle.value) idle.value = false;
    _timer?.cancel();
    _timer = Timer(timeout, () => idle.value = true);
  }
}

/// Fades [child] out while the user is idle and back in on any input.
class IdleFade extends StatefulWidget {
  const IdleFade({super.key, required this.child});

  final Widget child;

  @override
  State<IdleFade> createState() => _IdleFadeState();
}

class _IdleFadeState extends State<IdleFade> {
  @override
  void initState() {
    super.initState();
    InputIdle.instance.ensureInstalled();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: InputIdle.instance.idle,
      builder: (_, idle, child) => IgnorePointer(
        ignoring: idle,
        child: AnimatedOpacity(
          opacity: idle ? 0 : 1,
          duration: const Duration(milliseconds: 250),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
