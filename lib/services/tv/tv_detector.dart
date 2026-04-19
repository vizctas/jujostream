import 'dart:io' show Platform;
import 'package:flutter/services.dart';

class TvDetector {
  TvDetector._();

  static final TvDetector instance = TvDetector._();

  static const _channel = MethodChannel('com.jujostream/tv_detector');

  bool _isTV = false;
  bool _isLowRam = false;

  bool get isTV => _isTV;

  bool get isLowRam => _isLowRam;

  double get fontScale => _isTV ? 1.35 : 1.0;

  double get spacingScale => _isTV ? 1.3 : 1.0;

  double get minTouchTarget => _isTV ? 56.0 : 48.0;

  Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      _isTV = await _channel.invokeMethod<bool>('isAndroidTV') ?? false;
      _isLowRam = await _channel.invokeMethod<bool>('isLowRamDevice') ?? false;
    } on MissingPluginException {
      _isTV = false;
      _isLowRam = false;
    }
  }
}
