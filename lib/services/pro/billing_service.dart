import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:logger/logger.dart';

class BillingService extends ChangeNotifier {
  BillingService._();
  static final BillingService _instance = BillingService._();
  factory BillingService() => _instance;

  static const String kProductId = 'jujostream_pro';
  static final _log = Logger(printer: SimplePrinter());

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool _available = false;
  bool _purchased = false;
  bool _loading = true;
  ProductDetails? _product;
  String? _error;

  bool get isAvailable => _available;
  bool get isPurchased => _purchased;
  bool get isLoading => _loading;
  ProductDetails? get product => _product;
  String? get error => _error;

  Future<void> initialize() async {
    if (!Platform.isAndroid) {
      _loading = false;
      return;
    }

    _available = await _iap.isAvailable();
    if (!_available) {
      _log.w('[Billing] Store not available');
      _loading = false;
      notifyListeners();
      return;
    }

    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _sub?.cancel(),
      onError: (e) => _log.e('[Billing] Stream error: $e'),
    );

    await _loadProducts();

    await restorePurchases();

    _loading = false;
    notifyListeners();
  }

  Future<void> _loadProducts() async {
    final response = await _iap.queryProductDetails({kProductId});
    if (response.error != null) {
      _error = response.error!.message;
      _log.e('[Billing] Product query error: $_error');
      return;
    }
    if (response.notFoundIDs.isNotEmpty) {
      _log.w('[Billing] Product not found: ${response.notFoundIDs}');

      return;
    }
    if (response.productDetails.isNotEmpty) {
      _product = response.productDetails.first;
      _log.i('[Billing] Product loaded: ${_product!.title} — ${_product!.price}');
    }
  }

  bool buyPro() {
    if (_product == null) {
      _error = 'Product not available';
      notifyListeners();
      return false;
    }
    final param = PurchaseParam(productDetails: _product!);

    _iap.buyNonConsumable(purchaseParam: param);
    return true;
  }

  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final p in purchases) {
      _handlePurchase(p);
    }
  }

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    if (purchase.productID != kProductId) return;

    switch (purchase.status) {
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        _purchased = true;
        _error = null;
        _log.i('[Billing] Pro purchased/restored ✓');
        notifyListeners();
        break;

      case PurchaseStatus.error:
        _purchased = false;
        _error = purchase.error?.message ?? 'Purchase failed';
        _log.e('[Billing] Purchase error: $_error');
        notifyListeners();
        break;

      case PurchaseStatus.canceled:
        _error = null;
        _log.i('[Billing] Purchase canceled');
        notifyListeners();
        break;

      case PurchaseStatus.pending:
        _log.i('[Billing] Purchase pending...');
        break;
    }

    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
