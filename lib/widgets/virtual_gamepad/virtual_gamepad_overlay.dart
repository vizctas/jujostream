import 'package:flutter/material.dart';
import '../../platform_channels/streaming_channel.dart';
import 'virtual_joystick.dart';
import 'virtual_button.dart';

class VirtualGamepadOverlay extends StatefulWidget {
  final bool visible;
  final double opacity;
  final int controllerNumber;
  final int activeGamepadMask;

  const VirtualGamepadOverlay({
    super.key,
    this.visible = true,
    this.opacity = 0.6,
    this.controllerNumber = 0,
    this.activeGamepadMask = 1,
  });

  @override
  State<VirtualGamepadOverlay> createState() => _VirtualGamepadOverlayState();
}

class _VirtualGamepadOverlayState extends State<VirtualGamepadOverlay> {

  static const int _btnA = 0x1000;
  static const int _btnB = 0x2000;
  static const int _btnX = 0x4000;
  static const int _btnY = 0x8000;
  static const int _btnUp = 0x0001;
  static const int _btnDown = 0x0002;
  static const int _btnLeft = 0x0004;
  static const int _btnRight = 0x0008;
  static const int _btnStart = 0x0010;
  static const int _btnBack = 0x0020;
  static const int _btnLB = 0x0100;
  static const int _btnRB = 0x0200;

  int _buttonFlags = 0;
  int _leftTrigger = 0;
  int _rightTrigger = 0;
  int _leftStickX = 0;
  int _leftStickY = 0;
  int _rightStickX = 0;
  int _rightStickY = 0;

  void _setButton(int flag, bool pressed) {
    setState(() {
      if (pressed) {
        _buttonFlags |= flag;
      } else {
        _buttonFlags &= ~flag;
      }
    });
    _sendInput();
  }

  void _sendInput() {
    StreamingPlatformChannel.sendGamepadInput(
      buttonFlags: _buttonFlags,
      leftTrigger: _leftTrigger,
      rightTrigger: _rightTrigger,
      leftStickX: _leftStickX,
      leftStickY: _leftStickY,
      rightStickX: _rightStickX,
      rightStickY: _rightStickY,
      controllerNumber: widget.controllerNumber,
      activeGamepadMask: widget.activeGamepadMask,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();

    return Opacity(
      opacity: widget.opacity,
      child: IgnorePointer(
        ignoring: false,
        child: Stack(
          children: [

            Positioned(
              left: 24,
              bottom: 24,
              child: VirtualJoystick(
                size: 130,
                onChanged: (offset) {
                  _leftStickX = (offset.dx * 32767).toInt().clamp(-32768, 32767);
                  _leftStickY = (offset.dy * 32767).toInt().clamp(-32768, 32767);
                  _sendInput();
                },
              ),
            ),

            Positioned(
              left: 24,
              bottom: 180,
              child: _buildDpad(),
            ),

            Positioned(
              right: 24,
              bottom: 24,
              child: VirtualJoystick(
                size: 130,
                onChanged: (offset) {
                  _rightStickX = (offset.dx * 32767).toInt().clamp(-32768, 32767);
                  _rightStickY = (offset.dy * 32767).toInt().clamp(-32768, 32767);
                  _sendInput();
                },
              ),
            ),

            Positioned(
              right: 24,
              bottom: 180,
              child: _buildFaceButtons(),
            ),

            Positioned(
              left: 24,
              top: 24,
              child: _buildShoulderButton('LB', _btnLB),
            ),
            Positioned(
              right: 24,
              top: 24,
              child: _buildShoulderButton('RB', _btnRB),
            ),

            Positioned(
              left: 90,
              top: 24,
              child: _buildTrigger('LT', true),
            ),
            Positioned(
              right: 90,
              top: 24,
              child: _buildTrigger('RT', false),
            ),

            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  VirtualButton(
                    label: '⊟',
                    size: 36,
                    onPressed: () => _setButton(_btnBack, true),
                    onReleased: () => _setButton(_btnBack, false),
                  ),
                  const SizedBox(width: 40),
                  VirtualButton(
                    label: '⊞',
                    size: 36,
                    onPressed: () => _setButton(_btnStart, true),
                    onReleased: () => _setButton(_btnStart, false),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDpad() {
    const size = 45.0;
    const gap = 2.0;
    return SizedBox(
      width: size * 3 + gap * 2,
      height: size * 3 + gap * 2,
      child: Stack(
        children: [

          Positioned(
            left: size + gap,
            top: 0,
            child: VirtualButton(
              icon: Icons.arrow_drop_up,
              size: size,
              onPressed: () => _setButton(_btnUp, true),
              onReleased: () => _setButton(_btnUp, false),
            ),
          ),

          Positioned(
            left: size + gap,
            bottom: 0,
            child: VirtualButton(
              icon: Icons.arrow_drop_down,
              size: size,
              onPressed: () => _setButton(_btnDown, true),
              onReleased: () => _setButton(_btnDown, false),
            ),
          ),

          Positioned(
            left: 0,
            top: size + gap,
            child: VirtualButton(
              icon: Icons.arrow_left,
              size: size,
              onPressed: () => _setButton(_btnLeft, true),
              onReleased: () => _setButton(_btnLeft, false),
            ),
          ),

          Positioned(
            right: 0,
            top: size + gap,
            child: VirtualButton(
              icon: Icons.arrow_right,
              size: size,
              onPressed: () => _setButton(_btnRight, true),
              onReleased: () => _setButton(_btnRight, false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaceButtons() {
    const size = 48.0;
    return SizedBox(
      width: size * 3,
      height: size * 3,
      child: Stack(
        children: [

          Positioned(
            left: size,
            top: 0,
            child: VirtualButton(
              label: 'Y',
              size: size,
              color: Colors.yellowAccent,
              onPressed: () => _setButton(_btnY, true),
              onReleased: () => _setButton(_btnY, false),
            ),
          ),

          Positioned(
            left: size,
            bottom: 0,
            child: VirtualButton(
              label: 'A',
              size: size,
              color: Colors.greenAccent,
              onPressed: () => _setButton(_btnA, true),
              onReleased: () => _setButton(_btnA, false),
            ),
          ),

          Positioned(
            left: 0,
            top: size,
            child: VirtualButton(
              label: 'X',
              size: size,
              color: Colors.blueAccent,
              onPressed: () => _setButton(_btnX, true),
              onReleased: () => _setButton(_btnX, false),
            ),
          ),

          Positioned(
            right: 0,
            top: size,
            child: VirtualButton(
              label: 'B',
              size: size,
              color: Colors.redAccent,
              onPressed: () => _setButton(_btnB, true),
              onReleased: () => _setButton(_btnB, false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShoulderButton(String label, int flag) {
    return GestureDetector(
      onTapDown: (_) => _setButton(flag, true),
      onTapUp: (_) => _setButton(flag, false),
      onTapCancel: () => _setButton(flag, false),
      child: Container(
        width: 60,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: (_buttonFlags & flag) != 0
              ? Colors.white30
              : Colors.white12,
          border: Border.all(color: Colors.white24, width: 1.5),
        ),
        child: Center(
          child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ),
      ),
    );
  }

  Widget _buildTrigger(String label, bool isLeft) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() {
          if (isLeft) {
            _leftTrigger = 255;
          } else {
            _rightTrigger = 255;
          }
        });
        _sendInput();
      },
      onTapUp: (_) {
        setState(() {
          if (isLeft) {
            _leftTrigger = 0;
          } else {
            _rightTrigger = 0;
          }
        });
        _sendInput();
      },
      onTapCancel: () {
        setState(() {
          if (isLeft) {
            _leftTrigger = 0;
          } else {
            _rightTrigger = 0;
          }
        });
        _sendInput();
      },
      child: Container(
        width: 50,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: (isLeft ? _leftTrigger : _rightTrigger) > 0
              ? Colors.white30
              : Colors.white12,
          border: Border.all(color: Colors.white24, width: 1.5),
        ),
        child: Center(
          child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ),
      ),
    );
  }
}
