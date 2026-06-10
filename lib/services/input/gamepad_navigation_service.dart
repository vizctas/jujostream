import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../platform_channels/gamepad_channel.dart';

/// Translates WGI/XInput nav events (sent via MethodChannel) into Flutter
/// focus-system traversal. Works app-wide without touching individual screens.
class GamepadNavigationService {
  GamepadNavigationService._();

  static bool _active = true;
  // Guards the Dart 'back' nav event (background path on Windows) while an
  // in-app on-screen keyboard is open; foreground B/Escape is handled by the
  // focused screen itself.
  static bool _suppressBack = false;

  /// Aux buttons ('x','y','lb','rb','start') are only delivered to an
  /// explicitly registered handler (e.g. the cloud auth screen) and never
  /// fall through to focus traversal.
  static void Function(String button)? _auxButtonHandler;

  static void setAuxButtonHandler(void Function(String button)? handler) {
    _auxButtonHandler = handler;
  }

  /// Clears the handler only if [handler] is still the registered one, so a
  /// disposing screen can't clobber a registration made by another instance.
  static void clearAuxButtonHandler(void Function(String button) handler) {
    if (identical(_auxButtonHandler, handler)) _auxButtonHandler = null;
  }

  static void init() {
    GamepadChannel.onNavInput = _onNav;
  }

  static void setActive(bool active) {
    _active = active;
  }

  static void setSuppressBack(bool value) {
    _suppressBack = value;
  }

  static void _onNav(String key) {
    if (!_active) return;

    if (key == 'x' || key == 'y' || key == 'lb' || key == 'rb' || key == 'start') {
      _auxButtonHandler?.call(key);
      return;
    }

    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return;
    final context = focus.context;

    final isKeyboardVisible = context != null &&
        context.mounted &&
        (MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0) > 0;

    final isEditable =
        focus.context?.widget is EditableText ||
        focus.context?.findAncestorWidgetOfExactType<EditableText>() != null;

    if (isKeyboardVisible || isEditable) {
      if (key == 'back') {
        focus.unfocus();
        SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      } else if (!isKeyboardVisible) {
        if (key == 'down') {
          _traverse(TraversalDirection.down);
        } else if (key == 'up') {
          _traverse(TraversalDirection.up);
        }
      }
      // Ignore other inputs (like left/right) while typing to prevent cursor conflicts
      // If keyboard is visible, also ignore up/down so OS keyboard can consume them
      return;
    }


    switch (key) {
      case 'up':
        _traverse(TraversalDirection.up);
      case 'down':
        _traverse(TraversalDirection.down);
      case 'left':
        _traverse(TraversalDirection.left);
      case 'right':
        _traverse(TraversalDirection.right);
      case 'select':
        _activateFocused();
      case 'back':
        if (_suppressBack) return;
        _goBack();
    }
  }

  static void _traverse(TraversalDirection dir) {
    final focus =
        FocusManager.instance.primaryFocus ?? FocusManager.instance.rootScope;
    focus.focusInDirection(dir);
  }

  static void _activateFocused() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return;
    // Dispatch an Enter key event directly through the focus node's context
    final context = focus.context;
    if (context == null) return;
    Actions.maybeInvoke(context, const ActivateIntent());
  }

  static void _goBack() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return;
    final context = focus.context;
    if (context == null) return;
    // Try escape intent first (dismisses dialogs, bottom sheets, etc.)
    final handled = Actions.maybeInvoke(context, const DismissIntent());
    if (handled == null) {
      // Fall back to Navigator.pop
      final navigator = Navigator.maybeOf(context);
      navigator?.maybePop();
    }
  }
}
