import 'package:flutter/services.dart';

/// `jujostream://invite/…` links delivered by MainActivity (cold start
/// through [getInitialLink], while running through `onLink`).
class InviteLinkChannel {
  static const _channel = MethodChannel('com.jujostream/invite_link');

  static Future<void> listen(void Function(String link) onLink) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLink') onLink(call.arguments as String);
    });
    try {
      final initial = await _channel.invokeMethod<String>('getInitialLink');
      if (initial != null) onLink(initial);
    } on MissingPluginException {
      // Not Android.
    }
  }
}
