import 'package:flutter/material.dart';

/// Callback to send absolute mouse position to the stream.
typedef MousePositionCallback = void Function(int x, int y, int width, int height);

/// Callback to send a mouse button press/release.
typedef MouseButtonCallback = void Function(int button, bool down);

/// Callback to send a raw multi-touch event.
typedef TouchEventCallback = void Function({
  required int eventType,
  required int pointerId,
  required double x,
  required double y,
  required double pressure,
  required double contactMajor,
  required double contactMinor,
  required int orientation,
  required double refWidth,
  required double refHeight,
});

/// Callback to convert a screen-space touch position to stream coordinates.
typedef TouchToStreamCoordsCallback = (int x, int y) Function(Offset touchPos);

/// Callback to update the local cursor overlay position.
typedef UpdateLocalCursorCallback = void Function(double px, double py);

/// Handles direct touch and absolute touch input for the stream screen.
///
/// Handles two input modes:
/// - **Absolute touch** (multi-touch passthrough): forwards raw pointer events
///   as touch events to the streaming server.
/// - **Direct touch** (point-and-click): emulates mouse clicks via tap/long-press
///   gestures with dead-zone, double-tap drag, and long-press right-click.
class DirectTouchHandler {
  DirectTouchHandler({
    required this.onMousePosition,
    required this.onMouseButton,
    required this.onTouchEvent,
    required this.touchToStreamCoords,
    required this.updateLocalCursor,
    required this.isMounted,
    required this.getScreenSize,
    required this.getStreamWidth,
    required this.getStreamHeight,
  });

  final MousePositionCallback onMousePosition;
  final MouseButtonCallback onMouseButton;
  final TouchEventCallback onTouchEvent;
  final TouchToStreamCoordsCallback touchToStreamCoords;
  final UpdateLocalCursorCallback updateLocalCursor;
  final bool Function() isMounted;
  final Size Function() getScreenSize;
  final int Function() getStreamWidth;
  final int Function() getStreamHeight;

  // ── State: direct touch (point-and-click) ──────────────────────────────

  int _touchDownX = 0, _touchDownY = 0;
  int _touchUpX = 0, _touchUpY = 0;
  int _touchUpTime = 0;
  bool _cancelled = false;
  bool _confirmedLongPress = false;
  bool _confirmedTap = false;
  int _pointerCount = 0;

  int? _longPressTimerId;
  int? _tapDownTimerId;
  int _timerIdCounter = 0;

  // ── Constants ──────────────────────────────────────────────────────────

  static const int _longPressThresholdMs = 650;
  static const int _longPressDistThreshold = 30;
  static const int _doubleTapTimeThreshold = 250;
  static const int _doubleTapDistThreshold = 60;
  static const int _tapDownDeadZoneTime = 100;
  static const int _tapDownDeadZoneDist = 20;

  static const int btnLeft = 1;
  static const int btnRight = 3;

  // ── Helpers ────────────────────────────────────────────────────────────

  bool _distanceExceeds(int dx, int dy, double limit) {
    return (dx * dx + dy * dy) > (limit * limit);
  }

  void _updatePosition(int eventX, int eventY) {
    final screenSize = getScreenSize();
    final x = eventX.clamp(0, screenSize.width.toInt());
    final y = eventY.clamp(0, screenSize.height.toInt());
    final (sx, sy) = touchToStreamCoords(Offset(x.toDouble(), y.toDouble()));
    onMousePosition(sx, sy, getStreamWidth(), getStreamHeight());
    updateLocalCursor(x.toDouble(), y.toDouble());
  }

  // ── Tap / long-press state machine ─────────────────────────────────────

  void _tapConfirmed() {
    if (_confirmedTap || _confirmedLongPress) return;
    _confirmedTap = true;
    _cancelTapDownTimer();

    final now = DateTime.now().millisecondsSinceEpoch;
    if ((now - _touchUpTime) > _doubleTapTimeThreshold ||
        _distanceExceeds(
          _touchDownX - _touchUpX,
          _touchDownY - _touchUpY,
          _doubleTapDistThreshold.toDouble(),
        )) {
      _updatePosition(_touchDownX, _touchDownY);
    }
    onMouseButton(btnLeft, true);
  }

  void _startLongPressTimer() {
    _cancelLongPressTimer();
    final id = ++_timerIdCounter;
    _longPressTimerId = id;
    Future.delayed(const Duration(milliseconds: _longPressThresholdMs), () {
      if (_longPressTimerId != id || !isMounted()) return;
      _cancelTapDownTimer();
      _confirmedLongPress = true;
      if (_confirmedTap) {
        onMouseButton(btnLeft, false);
      }
      onMouseButton(btnRight, true);
    });
  }

  void _cancelLongPressTimer() {
    _longPressTimerId = null;
  }

  void _startTapDownTimer() {
    _cancelTapDownTimer();
    final id = ++_timerIdCounter;
    _tapDownTimerId = id;
    Future.delayed(const Duration(milliseconds: _tapDownDeadZoneTime), () {
      if (_tapDownTimerId != id || !isMounted()) return;
      _tapConfirmed();
    });
  }

  void _cancelTapDownTimer() {
    _tapDownTimerId = null;
  }

  // ── Public: build absolute touch layer (multi-touch passthrough) ───────

  /// Returns a [Listener] widget that forwards raw multi-touch events.
  ///
  /// Coordinates are normalized from screen-space to stream-space using
  /// [touchToStreamCoords] so the server receives positions relative to
  /// the stream resolution, not the device display.
  Widget buildAbsoluteTouchInputLayer() {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        final (sx, sy) = touchToStreamCoords(event.localPosition);
        final sw = getStreamWidth().toDouble();
        final sh = getStreamHeight().toDouble();
        onTouchEvent(
          eventType: 0x01, // ACTION_DOWN / POINTER_DOWN
          pointerId: event.pointer,
          x: sx.toDouble(),
          y: sy.toDouble(),
          pressure: event.pressure,
          contactMajor: event.size,
          contactMinor: event.size,
          orientation: event.orientation.toInt(),
          refWidth: sw,
          refHeight: sh,
        );
      },
      onPointerMove: (event) {
        final (sx, sy) = touchToStreamCoords(event.localPosition);
        final sw = getStreamWidth().toDouble();
        final sh = getStreamHeight().toDouble();
        onTouchEvent(
          eventType: 0x02, // ACTION_MOVE
          pointerId: event.pointer,
          x: sx.toDouble(),
          y: sy.toDouble(),
          pressure: event.pressure,
          contactMajor: event.size,
          contactMinor: event.size,
          orientation: event.orientation.toInt(),
          refWidth: sw,
          refHeight: sh,
        );
      },
      onPointerUp: (event) {
        final (sx, sy) = touchToStreamCoords(event.localPosition);
        final sw = getStreamWidth().toDouble();
        final sh = getStreamHeight().toDouble();
        onTouchEvent(
          eventType: 0x03, // ACTION_UP / POINTER_UP
          pointerId: event.pointer,
          x: sx.toDouble(),
          y: sy.toDouble(),
          pressure: event.pressure,
          contactMajor: event.size,
          contactMinor: event.size,
          orientation: event.orientation.toInt(),
          refWidth: sw,
          refHeight: sh,
        );
      },
      onPointerCancel: (event) {
        final (sx, sy) = touchToStreamCoords(event.localPosition);
        final sw = getStreamWidth().toDouble();
        final sh = getStreamHeight().toDouble();
        onTouchEvent(
          eventType: 0x04, // ACTION_CANCEL
          pointerId: event.pointer,
          x: sx.toDouble(),
          y: sy.toDouble(),
          pressure: event.pressure,
          contactMajor: event.size,
          contactMinor: event.size,
          orientation: event.orientation.toInt(),
          refWidth: sw,
          refHeight: sh,
        );
      },
    );
  }

  // ── Public: build direct touch layer (point-and-click emulation) ───────

  /// Returns a [Listener] widget that emulates mouse clicks via touch gestures.
  Widget buildDirectTouchInputLayer() {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _pointerCount++;
        if (_pointerCount > 1) {
          _cancelled = true;
          _cancelLongPressTimer();
          _cancelTapDownTimer();
          if (_confirmedLongPress) {
            onMouseButton(btnRight, false);
          } else if (_confirmedTap) {
            onMouseButton(btnLeft, false);
          }
          return;
        }
        final x = event.localPosition.dx.toInt();
        final y = event.localPosition.dy.toInt();
        _touchDownX = x;
        _touchDownY = y;
        _cancelled = false;
        _confirmedTap = false;
        _confirmedLongPress = false;
        _startTapDownTimer();
        _startLongPressTimer();
      },
      onPointerMove: (event) {
        if (_cancelled || _pointerCount != 1) return;
        final x = event.localPosition.dx.toInt();
        final y = event.localPosition.dy.toInt();

        if (_distanceExceeds(
          x - _touchDownX,
          y - _touchDownY,
          _longPressDistThreshold.toDouble(),
        )) {
          _cancelLongPressTimer();
        }

        if (_confirmedTap ||
            _distanceExceeds(
              x - _touchDownX,
              y - _touchDownY,
              _tapDownDeadZoneDist.toDouble(),
            )) {
          _tapConfirmed();
          _updatePosition(x, y);
        }
      },
      onPointerUp: (event) {
        _pointerCount = (_pointerCount - 1).clamp(0, 10);
        if (_cancelled) return;

        _cancelLongPressTimer();
        _cancelTapDownTimer();

        if (_confirmedLongPress) {
          onMouseButton(btnRight, false);
        } else if (_confirmedTap) {
          onMouseButton(btnLeft, false);
        } else {
          _tapConfirmed();
          Future.delayed(const Duration(milliseconds: 100), () {
            onMouseButton(btnLeft, false);
          });
        }

        final x = event.localPosition.dx.toInt();
        final y = event.localPosition.dy.toInt();
        _touchUpX = x;
        _touchUpY = y;
        _touchUpTime = DateTime.now().millisecondsSinceEpoch;
      },
      onPointerCancel: (event) {
        _pointerCount = (_pointerCount - 1).clamp(0, 10);
        _cancelled = true;
        _cancelLongPressTimer();
        _cancelTapDownTimer();
        if (_confirmedLongPress) {
          onMouseButton(btnRight, false);
        } else if (_confirmedTap) {
          onMouseButton(btnLeft, false);
        }
      },
      // Double-tap removed: overlay must ONLY be triggered via the configured
      // combo (default or custom in Settings), never by screen double-tap.
      child: const SizedBox.expand(),
    );
  }
}
