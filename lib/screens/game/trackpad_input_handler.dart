import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// Callback signatures for trackpad events sent to the streaming channel.
typedef MouseMoveCallback = void Function(int dx, int dy);
typedef MouseButtonCallback = void Function(int button, bool pressed);
typedef ScrollCallback = void Function(int amount);
typedef HScrollCallback = void Function(int amount);

/// Self-contained trackpad gesture handler with momentum physics.
///
/// Extracted from `game_stream_screen.dart` to reduce the monolithic
/// 3793-line file. Encapsulates all trackpad state, tap/drag/scroll detection,
/// and flick momentum — exposing only typed callbacks for mouse/scroll events.
class TrackpadInputHandler {
  TrackpadInputHandler({
    required this.onMouseMove,
    required this.onMouseButton,
    required this.onScroll,
    required this.onHScroll,
    required this.isMounted,
  });

  final MouseMoveCallback onMouseMove;
  final MouseButtonCallback onMouseButton;
  final ScrollCallback onScroll;
  final HScrollCallback onHScroll;

  /// Must return true when the owning State is still mounted.
  final bool Function() isMounted;

  static const int btnLeft = 1;
  static const int btnRight = 3;
  static const int btnMiddle = 2;

  static const int _tapMovementThreshold = 30;
  static const int _tapTimeThreshold = 230;
  static const int _clickReleaseDelay = 230;
  static const int _scrollSpeedX = 2;
  static const int _scrollSpeedY = 3;
  static const double _accelThreshold = 8.0;
  static const double _flickFriction = 0.93;
  static const double _flickThreshold = 0.8;
  static const int _momentumInterval = 10;
  static const int _flickDecayTimeout = 50;
  static const int _scrollTransTimeout = 200;

  double _pendingDX = 0, _pendingDY = 0;
  int _lastX = 0, _lastY = 0;
  int _origX = 0, _origY = 0;
  int _origTime = 0;
  bool _cancelled = false;
  bool _confirmedMove = false;
  bool _confirmedDrag = false;
  bool _confirmedScroll = false;
  double _distanceMoved = 0;
  int _pointerCount = 0;
  int _maxPointers = 0;
  bool _clickPending = false;
  bool _dblClickPending = false;
  bool _isFlicking = false;
  double _velocityX = 0, _velocityY = 0;
  int _lastMoveTime = 0;
  bool _scrollTransitioning = false;
  bool _clickedMiddle = false;
  int _flickTimerId = 0;
  int _scrollTransTimerId = 0;

  /// Builds a [Listener] widget that handles all trackpad gestures.
  Widget buildInputLayer({
    required double sensitivityX,
    required double sensitivityY,
  }) {
    final sensX = sensitivityX / 100.0;
    final sensY = sensitivityY / 100.0;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _onPointerDown(event),
      onPointerMove: (event) => _onPointerMove(event, sensX, sensY),
      onPointerUp: (event) => _onPointerUp(event),
      onPointerCancel: (event) => _onPointerCancel(event),
      child: const SizedBox.expand(),
    );
  }

  int _getButton() {
    if (_pointerCount == 2) return btnRight;
    if (_pointerCount == 3) {
      _clickedMiddle = true;
      return btnMiddle;
    }
    return btnLeft;
  }

  bool _isWithinTapBounds(int x, int y) {
    return (x - _origX).abs() <= _tapMovementThreshold &&
        (y - _origY).abs() <= _tapMovementThreshold;
  }

  bool _isTap(int eventTime) {
    if (_confirmedDrag || _confirmedMove || _confirmedScroll) return false;
    return _isWithinTapBounds(_lastX, _lastY) &&
        (eventTime - _origTime) <= _tapTimeThreshold;
  }

  void _checkConfirmedMove(int x, int y) {
    if (_confirmedMove || _confirmedDrag) return;
    if (!_isWithinTapBounds(x, y)) {
      _confirmedMove = true;
      return;
    }
    _distanceMoved += _dist(x - _lastX, y - _lastY);
    if (_distanceMoved >= _tapMovementThreshold) _confirmedMove = true;
  }

  double _dist(int dx, int dy) => (dx * dx + dy * dy).toDouble();

  static double _cbrt(double x) {
    if (x == 0) return 0;
    if (x > 0) return math.pow(x, 1.0 / 3.0).toDouble();
    return -math.pow(-x, 1.0 / 3.0).toDouble();
  }

  void _startMomentum() {
    final id = ++_flickTimerId;
    void loop() {
      if (id != _flickTimerId || !_isFlicking || !isMounted()) return;
      _pendingDX += _velocityX * _momentumInterval;
      _pendingDY += _velocityY * _momentumInterval;
      final dx = _pendingDX.toInt();
      final dy = _pendingDY.toInt();
      if (dx != 0 || dy != 0) {
        onMouseMove(dx, dy);
        _pendingDX -= dx;
        _pendingDY -= dy;
      }
      _velocityX *= _flickFriction;
      _velocityY *= _flickFriction;
      final speed = (_velocityX * _velocityX + _velocityY * _velocityY);
      if (speed * _momentumInterval * _momentumInterval < 0.25) {
        _isFlicking = false;
        if (_confirmedDrag) {
          onMouseButton(_getButton(), false);
          _confirmedDrag = false;
        }
        return;
      }
      Future.delayed(const Duration(milliseconds: _momentumInterval), loop);
    }
    Future.delayed(const Duration(milliseconds: _momentumInterval), loop);
  }

  void _startScrollMomentum() {
    final id = ++_flickTimerId;
    void loop() {
      if (id != _flickTimerId || !_isFlicking || !isMounted()) return;
      final fvx = _velocityX * _momentumInterval;
      final fvy = _velocityY * _momentumInterval;
      if (fvx.abs() > fvy.abs()) {
        onHScroll((-fvx * _scrollSpeedX).toInt());
        if (fvy.abs() * 1.05 > fvx.abs()) {
          onScroll((fvy * _scrollSpeedY).toInt());
        }
      } else {
        onScroll((fvy * _scrollSpeedY).toInt());
        if (fvx.abs() * 1.05 >= fvy.abs()) {
          onHScroll((-fvx * _scrollSpeedX).toInt());
        }
      }
      _velocityX *= _flickFriction;
      _velocityY *= _flickFriction;
      final speed = (_velocityX * _velocityX + _velocityY * _velocityY);
      if (speed * _momentumInterval * _momentumInterval < 0.25) {
        _isFlicking = false;
        return;
      }
      Future.delayed(const Duration(milliseconds: _momentumInterval), loop);
    }
    Future.delayed(const Duration(milliseconds: _momentumInterval), loop);
  }

  void _onPointerDown(PointerDownEvent event) {
    final prevCount = _pointerCount;
    _pointerCount++;

    if (_isFlicking) {
      _isFlicking = false;
      _flickTimerId++;
    }

    final x = event.localPosition.dx.toInt();
    final y = event.localPosition.dy.toInt();

    final isNewFinger = (prevCount == 0);
    if (isNewFinger) {
      _clickedMiddle = false;
      _scrollTransitioning = false;
      _scrollTransTimerId++;
      _maxPointers = _pointerCount;
      _origX = _lastX = x;
      _origY = _lastY = y;
      _origTime = DateTime.now().millisecondsSinceEpoch;
      _cancelled = false;
      _confirmedMove = false;
      _confirmedScroll = false;
      _distanceMoved = 0;
      _velocityX = 0;
      _velocityY = 0;
      _lastMoveTime = _origTime;
      _pendingDX = 0;
      _pendingDY = 0;
      if (_clickPending) {
        _clickPending = false;
        _dblClickPending = true;
        _confirmedDrag = true;
      }
    } else {
      if (_pointerCount == 2 && !_confirmedMove && !_clickedMiddle) {
        onMouseButton(btnRight, true);
        onMouseButton(btnRight, false);
        _clickPending = false;
        _dblClickPending = false;
        _confirmedDrag = false;
        _clickedMiddle = false;
      }
      _origX = _lastX = x;
      _origY = _lastY = y;
      _pendingDX = 0;
      _pendingDY = 0;
    }

    if (_pointerCount > _maxPointers) _maxPointers = _pointerCount;
  }

  void _onPointerMove(PointerMoveEvent event, double sensX, double sensY) {
    if (_cancelled) return;
    final x = event.localPosition.dx.toInt();
    final y = event.localPosition.dy.toInt();
    if (x == _lastX && y == _lastY) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final deltaTime = now - _lastMoveTime;

    _checkConfirmedMove(x, y);

    if (_dblClickPending) {
      _dblClickPending = false;
      _confirmedDrag = true;
    }

    final rawDX = x - _lastX;
    final rawDY = y - _lastY;
    final magnitude = (rawDX * rawDX + rawDY * rawDY).toDouble();
    final precisionMul = _cbrt(magnitude / _accelThreshold);

    double deltaX = rawDX * precisionMul * sensX;
    double deltaY = rawDY * precisionMul * sensY;

    if (deltaTime > 0 && (_confirmedMove || _confirmedDrag)) {
      final cvx = deltaX / deltaTime;
      final cvy = deltaY / deltaTime;
      if (_velocityX == 0 && _velocityY == 0) {
        _velocityX = cvx;
        _velocityY = cvy;
      } else {
        _velocityX = _velocityX * 0.8 + cvx * 0.2;
        _velocityY = _velocityY * 0.8 + cvy * 0.2;
      }
    }
    _lastMoveTime = now;

    _pendingDX += deltaX;
    _pendingDY += deltaY;
    _lastX = x;
    _lastY = y;

    final sendDX = _pendingDX.toInt();
    final sendDY = _pendingDY.toInt();

    if (_pointerCount == 1) {
      if (!_scrollTransitioning && (sendDX != 0 || sendDY != 0)) {
        onMouseMove(sendDX, sendDY);
      }
    } else if (_pointerCount == 2) {
      if (_confirmedDrag) {
        if (sendDX != 0 || sendDY != 0) {
          onMouseMove(sendDX, sendDY);
        }
      } else {
        _confirmedScroll = _confirmedMove;
        if (_confirmedScroll) {
          final absDX = rawDX.abs();
          final absDY = rawDY.abs();
          if (absDX > absDY) {
            onHScroll(-sendDX * _scrollSpeedX);
            if (absDY * 1.05 > absDX) {
              onScroll(sendDY * _scrollSpeedY);
            }
          } else {
            onScroll(sendDY * _scrollSpeedY);
            if (absDX * 1.05 >= absDY) {
              onHScroll(-sendDX * _scrollSpeedX);
            }
          }
        }
      }
    }

    _pendingDX -= sendDX;
    _pendingDY -= sendDY;
  }

  void _onPointerUp(PointerUpEvent event) {
    final prevCount = _pointerCount;
    _pointerCount = (_pointerCount - 1).clamp(0, 10);

    if (prevCount == 2 && _pointerCount == 1) {
      _scrollTransitioning = true;
      final id = ++_scrollTransTimerId;
      Future.delayed(
        const Duration(milliseconds: _scrollTransTimeout),
        () {
          if (id == _scrollTransTimerId) _scrollTransitioning = false;
        },
      );
    }

    if (_pointerCount < prevCount && _confirmedDrag && !_isFlicking) {
      onMouseButton(_getButton(), false);
      _confirmedDrag = false;
      _confirmedMove = false;
      _confirmedScroll = false;
      _clickPending = false;
      _dblClickPending = false;
    }

    if (_pointerCount > 0 || _cancelled) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    final timeSinceMove = now - _lastMoveTime;
    if (timeSinceMove > 0) {
      final decay = (1.0 - timeSinceMove / _flickDecayTimeout).clamp(0.0, 1.0);
      _velocityX *= decay;
      _velocityY *= decay;
    }

    final button = _getButton();

    if (_dblClickPending) {
      onMouseButton(button, false);
      onMouseButton(button, true);
      onMouseButton(button, false);
      _clickPending = false;
      _confirmedDrag = false;
    } else if (_confirmedDrag) {
      final speed = _velocityX * _velocityX + _velocityY * _velocityY;
      if (speed > _flickThreshold * _flickThreshold) {
        _isFlicking = true;
        _startMomentum();
      } else {
        onMouseButton(button, false);
        _confirmedDrag = false;
      }
    } else if (_isTap(now)) {
      onMouseButton(button, true);
      _clickPending = true;
      final id = ++_flickTimerId;
      Future.delayed(
        const Duration(milliseconds: _clickReleaseDelay),
        () {
          if (id != _flickTimerId || !isMounted()) return;
          if (_clickPending) {
            onMouseButton(button, false);
            _clickPending = false;
          }
          _dblClickPending = false;
        },
      );
    } else if (_confirmedMove) {
      final speed = _velocityX * _velocityX + _velocityY * _velocityY;
      if (speed > _flickThreshold * _flickThreshold) {
        _isFlicking = true;
        if (_confirmedScroll) {
          _startScrollMomentum();
        } else if (_maxPointers == 1) {
          _startMomentum();
        }
      }
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointerCount = (_pointerCount - 1).clamp(0, 10);
    _cancelled = true;
    if (_isFlicking) {
      _isFlicking = false;
      _flickTimerId++;
    }
    if (_confirmedDrag) {
      onMouseButton(_getButton(), false);
    }
  }
}
