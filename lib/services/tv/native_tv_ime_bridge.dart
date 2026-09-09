import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum NativeTvImeInput { email, password, number }

/// Connects a Flutter controller to a real Android EditText while the system
/// TV keyboard is open. Chromecast's Gboard then owns DPAD navigation instead
/// of routing arrow keys back through Flutter's EditableText.
class NativeTvImeBridge {
  NativeTvImeBridge._() {
    _channel.setMethodCallHandler(_handleNativeEvent);
  }

  static final NativeTvImeBridge instance = NativeTvImeBridge._();
  static const _channel = MethodChannel('com.jujostream/native_tv_ime');

  _NativeTvImeSession? _session;

  Future<void> open({
    required String fieldId,
    required TextEditingController controller,
    required NativeTvImeInput input,
    required TextInputAction action,
    required VoidCallback onSubmitted,
    required VoidCallback onClosed,
    ValueChanged<String>? onChanged,
    int? maxLength,
  }) async {
    _session = _NativeTvImeSession(
      fieldId: fieldId,
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onClosed: onClosed,
    );

    try {
      await _channel.invokeMethod<void>('open', <String, Object?>{
        'fieldId': fieldId,
        'text': controller.text,
        'input': input.name,
        'action': action == TextInputAction.next ? 'next' : 'done',
        'maxLength': maxLength,
      });
    } on MissingPluginException {
      _session = null;
      rethrow;
    }
  }

  Future<void> close() async {
    _session = null;
    try {
      await _channel.invokeMethod<void>('close');
    } on MissingPluginException {
      // Non-Android test and desktop builds do not register the bridge.
    }
  }

  Future<void> _handleNativeEvent(MethodCall call) async {
    final arguments = call.arguments;
    if (arguments is! Map) return;
    final fieldId = arguments['fieldId'] as String?;
    final session = _session;
    if (session == null || session.fieldId != fieldId) return;

    switch (call.method) {
      case 'onChanged':
        final text = arguments['text'] as String? ?? '';
        session.controller.value = session.controller.value.copyWith(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
          composing: TextRange.empty,
        );
        session.onChanged?.call(text);
        return;
      case 'onSubmitted':
        session.onSubmitted();
        return;
      case 'onClosed':
        _session = null;
        session.onClosed();
        return;
      default:
        debugPrint('[NativeTvIme] Unknown native event: ${call.method}');
        return;
    }
  }
}

class _NativeTvImeSession {
  const _NativeTvImeSession({
    required this.fieldId,
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClosed,
  });

  final String fieldId;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback onSubmitted;
  final VoidCallback onClosed;
}
