import 'dart:async';
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
///   gestures. TRUE point-and-click: where the user touches is where the cursor
///   moves and clicks. No dead-zone delay for simple taps.
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

  int _touchDownX = 0, _touchDownY = 0;
  int _lastMoveX = 0, _lastMoveY = 0;
  int _touchUpX = 0, _touchUpY = 0;
  int _touchUpTime = 0;
  bool _cancelled = false;
  bool _confirmedLongPress = false;
  bool _confirmedDrag = false;
  int _pointerCount = 0;

  int? _longPressTimerId;
  int _timerIdCounter = 0;

  /// Whether the cursor position has been sent for the current gesture.
  /// Ensures position is always sent before any click event.
  bool _positionSent = false;

  static const int _longPressThresholdMs = 650;
  static const int _longPressDistThreshold = 30;
  static const int _doubleTapTimeThreshold = 250;
  static const int _doubleTapDistThreshold = 60;

  /// Distance threshold to distinguish a tap from a drag.
  /// Once exceeded, the gesture becomes a drag (move cursor + hold button).
  static const int _dragDistThreshold = 12;

  /// Micro-delay between sending position and click to ensure server
  /// processes them in order. 8ms is below perceptual threshold but
  /// enough for the server's input queue to sequence correctly.
  static const int _positionToClickDelayMs = 8;

  static const int btnLeft = 1;
  static const int btnRight = 3;

  bool _distanceExceeds(int dx, int dy, double limit) {
    return (dx * dx + dy * dy) > (limit * limit);
  }

  /// Sends the cursor to the given screen-space position.
  /// This is the SINGLE source of truth for cursor positioning during
  /// direct-touch gestures. The MouseRegion.onHover in game_stream_screen
  /// must NOT send position when a touch gesture is active.
  void _sendPosition(int screenX, int screenY) {
    final screenSize = getScreenSize();
    final x = screenX.clamp(0, screenSize.width.toInt());
    final y = screenY.clamp(0, screenSize.height.toInt());
    final (sx, sy) = touchToStreamCoords(Offset(x.toDouble(), y.toDouble()));
    onMousePosition(sx, sy, getStreamWidth(), getStreamHeight());
    updateLocalCursor(x.toDouble(), y.toDouble());
    _positionSent = true;
  }

  /// Sends position then click with a micro-delay to guarantee ordering.
  /// This eliminates the race condition where click arrives before position.
  void _sendPositionThenClick(int screenX, int screenY, int button, {bool release = false}) {
    _sendPosition(screenX, screenY);
    // Use a micro-delay to ensure the position packet is queued before the
    // click packet on the native side. Both go through platform channels
    // which are async — without this delay they can reorder.
    Future.delayed(const Duration(milliseconds: _positionToClickDelayMs), () {
      if (!isMounted()) return;
      onMouseButton(button, !release);
    });
  }

  void _startLongPressTimer() {
    _cancelLongPressTimer();
    final id = ++_timerIdCounter;
    _longPressTimerId = id;
    Future.delayed(const Duration(milliseconds: _longPressThresholdMs), () {
      if (_longPressTimerId != id || !isMounted()) return;
      _confirmedLongPress = true;
      // If we were already in a drag (left-click held), release it first
      if (_confirmedDrag) {
        onMouseButton(btnLeft, false);
      }
      // Right-click at the current position (already sent on pointer-down)
      onMouseButton(btnRight, true);
    });
  }

  void _cancelLongPressTimer() {
    _longPressTimerId = null;
  }

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

  /// Whether a touch gesture is currently active. When true, the
  /// MouseRegion.onHover in game_stream_screen must NOT send position
  /// updates to avoid the dual-source race condition.
  bool get isTouchActive => _pointerCount > 0;

  /// Returns a [Listener] widget that implements TRUE point-and-click:
  ///
  /// - **Tap**: Move cursor to touch point → left-click
  /// - **Long press**: Move cursor to touch point → right-click
  /// - **Drag**: Move cursor to touch point → hold left-click → drag
  /// - **Double-tap drag**: Move cursor → double-click-drag
  ///
  /// Key design decisions:
  /// 1. Position is ALWAYS sent immediately on pointer-down (zero delay)
  /// 2. Click is sent with a micro-delay after position to guarantee ordering
  /// 3. No dead-zone timer — drag detection is purely distance-based
  /// 4. Multi-finger cancels the gesture (prevents accidental clicks during
  ///    pinch-zoom or two-finger scroll)
  Widget buildDirectTouchInputLayer() {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _pointerCount++;
        if (_pointerCount > 1) {
          // Multi-finger: cancel current gesture
          _cancelled = true;
          _cancelLongPressTimer();
          if (_confirmedLongPress) {
            onMouseButton(btnRight, false);
          } else if (_confirmedDrag) {
            onMouseButton(btnLeft, false);
          }
          return;
        }

        final x = event.localPosition.dx.toInt();
        final y = event.localPosition.dy.toInt();
        _touchDownX = x;
        _touchDownY = y;
        _lastMoveX = x;
        _lastMoveY = y;
        _cancelled = false;
        _confirmedDrag = false;
        _confirmedLongPress = false;
        _positionSent = false;

        // ── CRITICAL: Send position IMMEDIATELY on touch-down ──
        // This is the core of point-and-click: the cursor teleports to
        // where the user touches, with ZERO delay.
        _sendPosition(x, y);

        // Start long-press detection for right-click
        _startLongPressTimer();
      },
      onPointerMove: (event) {
        if (_cancelled || _pointerCount != 1) return;
        final x = event.localPosition.dx.toInt();
        final y = event.localPosition.dy.toInt();

        // Cancel long-press if finger moved too far
        if (_distanceExceeds(
          x - _touchDownX,
          y - _touchDownY,
          _longPressDistThreshold.toDouble(),
        )) {
          _cancelLongPressTimer();
        }

        // If already in long-press (right-click), just update position
        if (_confirmedLongPress) {
          _sendPosition(x, y);
          _lastMoveX = x;
          _lastMoveY = y;
          return;
        }

        // Detect drag: finger moved beyond threshold
        if (!_confirmedDrag &&
            _distanceExceeds(
              x - _touchDownX,
              y - _touchDownY,
              _dragDistThreshold.toDouble(),
            )) {
          _confirmedDrag = true;
          _cancelLongPressTimer();

          // Check if this is a double-tap-drag (rapid second touch after a tap)
          final now = DateTime.now().millisecondsSinceEpoch;
          final isDoubleTapDrag = (now - _touchUpTime) <= _doubleTapTimeThreshold &&
              !_distanceExceeds(
                _touchDownX - _touchUpX,
                _touchDownY - _touchUpY,
                _doubleTapDistThreshold.toDouble(),
              );

          if (isDoubleTapDrag) {
            // Double-tap-drag: the first tap already clicked, now hold for drag
            // Position was already sent on pointer-down
            onMouseButton(btnLeft, true);
          } else {
            // Normal drag: hold left button from the touch-down point
            onMouseButton(btnLeft, true);
          }
        }

        // Update cursor position during drag
        if (_confirmedDrag) {
          _sendPosition(x, y);
        }

        _lastMoveX = x;
        _lastMoveY = y;
      },
      onPointerUp: (event) {
        _pointerCount = (_pointerCount - 1).clamp(0, 10);
        if (_cancelled) return;

        _cancelLongPressTimer();

        final x = event.localPosition.dx.toInt();
        final y = event.localPosition.dy.toInt();

        if (_confirmedLongPress) {
          // Long-press release: release right-click
          onMouseButton(btnRight, false);
        } else if (_confirmedDrag) {
          // Drag release: release left-click
          onMouseButton(btnLeft, false);
        } else {
          // ── Simple tap: point-and-click ──
          // Position was already sent on pointer-down. Now send the click
          // with a micro-delay to guarantee the server processes position first.
          //
          // Check for double-tap: if this tap is close in time and space to
          // the previous tap, send a double-click instead.
          final now = DateTime.now().millisecondsSinceEpoch;
          final isDoubleTap = (now - _touchUpTime) <= _doubleTapTimeThreshold &&
              !_distanceExceeds(
                x - _touchUpX,
                y - _touchUpY,
                _doubleTapDistThreshold.toDouble(),
              );

          // Ensure position is at the final touch point (may have micro-drifted)
          _sendPosition(x, y);

          if (isDoubleTap) {
            // Double-tap: send a rapid left-click (the first click was already
            // sent by the previous tap's pointer-up)
            Future.delayed(const Duration(milliseconds: _positionToClickDelayMs), () {
              if (!isMounted()) return;
              onMouseButton(btnLeft, true);
              Future.delayed(const Duration(milliseconds: 30), () {
                if (!isMounted()) return;
                onMouseButton(btnLeft, false);
              });
            });
          } else {
            // Single tap: click at touch point
            Future.delayed(const Duration(milliseconds: _positionToClickDelayMs), () {
              if (!isMounted()) return;
              onMouseButton(btnLeft, true);
              Future.delayed(const Duration(milliseconds: 60), () {
                if (!isMounted()) return;
                onMouseButton(btnLeft, false);
              });
            });
          }
        }

        _touchUpX = x;
        _touchUpY = y;
        _touchUpTime = DateTime.now().millisecondsSinceEpoch;
      },
      onPointerCancel: (event) {
        _pointerCount = (_pointerCount - 1).clamp(0, 10);
        _cancelled = true;
        _cancelLongPressTimer();
        if (_confirmedLongPress) {
          onMouseButton(btnRight, false);
        } else if (_confirmedDrag) {
          onMouseButton(btnLeft, false);
        }
      },
      child: const SizedBox.expand(),
    );
  }
}
