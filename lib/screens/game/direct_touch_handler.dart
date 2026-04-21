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

  /// Returns a [Listener] widget that forwards multi-touch events with
  /// **normalized 0.0–1.0 coordinates** as required by moonlight-common-c's
  /// `LiSendTouchEvent()`.
  ///
  /// From the protocol header (Limelight.h):
  /// > "The x and y values are normalized device coordinates stretching
  /// >  top-left corner (0.0, 0.0) to bottom-right corner (1.0, 1.0)
  /// >  of the video area."
  ///
  /// We divide `event.localPosition` by the Flutter view size to produce
  /// the 0.0–1.0 range. Contact area is also normalized by view size.
  Widget buildAbsoluteTouchInputLayer() {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        final sz = getScreenSize();
        final nx = (sz.width > 0) ? event.localPosition.dx / sz.width : 0.0;
        final ny = (sz.height > 0) ? event.localPosition.dy / sz.height : 0.0;
        onTouchEvent(
          eventType: 0x01, // ACTION_DOWN / POINTER_DOWN
          pointerId: event.pointer,
          x: nx.clamp(0.0, 1.0),
          y: ny.clamp(0.0, 1.0),
          pressure: event.pressure.clamp(0.0, 1.0),
          contactMajor: _normalizeContact(event.size, sz),
          contactMinor: _normalizeContact(event.size, sz),
          orientation: event.orientation.toInt(),
          refWidth: sz.width,
          refHeight: sz.height,
        );
      },
      onPointerMove: (event) {
        final sz = getScreenSize();
        final nx = (sz.width > 0) ? event.localPosition.dx / sz.width : 0.0;
        final ny = (sz.height > 0) ? event.localPosition.dy / sz.height : 0.0;
        onTouchEvent(
          eventType: 0x02, // ACTION_MOVE
          pointerId: event.pointer,
          x: nx.clamp(0.0, 1.0),
          y: ny.clamp(0.0, 1.0),
          pressure: event.pressure.clamp(0.0, 1.0),
          contactMajor: _normalizeContact(event.size, sz),
          contactMinor: _normalizeContact(event.size, sz),
          orientation: event.orientation.toInt(),
          refWidth: sz.width,
          refHeight: sz.height,
        );
      },
      onPointerUp: (event) {
        final sz = getScreenSize();
        final nx = (sz.width > 0) ? event.localPosition.dx / sz.width : 0.0;
        final ny = (sz.height > 0) ? event.localPosition.dy / sz.height : 0.0;
        onTouchEvent(
          eventType: 0x03, // ACTION_UP / POINTER_UP
          pointerId: event.pointer,
          x: nx.clamp(0.0, 1.0),
          y: ny.clamp(0.0, 1.0),
          pressure: event.pressure.clamp(0.0, 1.0),
          contactMajor: _normalizeContact(event.size, sz),
          contactMinor: _normalizeContact(event.size, sz),
          orientation: event.orientation.toInt(),
          refWidth: sz.width,
          refHeight: sz.height,
        );
      },
      onPointerCancel: (event) {
        final sz = getScreenSize();
        final nx = (sz.width > 0) ? event.localPosition.dx / sz.width : 0.0;
        final ny = (sz.height > 0) ? event.localPosition.dy / sz.height : 0.0;
        onTouchEvent(
          eventType: 0x04, // ACTION_CANCEL
          pointerId: event.pointer,
          x: nx.clamp(0.0, 1.0),
          y: ny.clamp(0.0, 1.0),
          pressure: event.pressure.clamp(0.0, 1.0),
          contactMajor: _normalizeContact(event.size, sz),
          contactMinor: _normalizeContact(event.size, sz),
          orientation: event.orientation.toInt(),
          refWidth: sz.width,
          refHeight: sz.height,
        );
      },
    );
  }

  /// Normalize contact area to 0.0–1.0 range relative to screen diagonal.
  /// Flutter's `PointerEvent.size` is already 0.0–1.0 on most platforms,
  /// but we clamp defensively.
  static double _normalizeContact(double size, Size screen) {
    return size.clamp(0.0, 1.0);
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
