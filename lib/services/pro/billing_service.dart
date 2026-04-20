import 'package:flutter/foundation.dart';

/// Stub billing service — all paid features are free.
///
/// This replaces the previous `in_app_purchase`-based implementation.
/// The interface is preserved so existing callers (ProService, ProGate)
/// compile without changes.
class BillingService extends ChangeNotifier {
  BillingService._();
  static final BillingService _instance = BillingService._();
  factory BillingService() => _instance;

  bool get isAvailable => false;
  bool get isPurchased => true; // everything is free
  bool get isLoading => false;
  dynamic get product => null;
  String? get error => null;

  Future<void> initialize() async {
    // No-op — billing removed.
  }

  bool buyPro() => false;

  Future<void> restorePurchases() async {}

  }
