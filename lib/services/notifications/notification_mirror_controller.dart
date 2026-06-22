import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/mirrored_notification.dart';
import '../../models/notification_mirror_pairing.dart';
import '../crypto/client_identity.dart';
import 'notification_mirror_platform.dart';
import 'notification_mirror_sender.dart';

enum NotificationMirrorMode {
  off,
  receiver,
  broadcaster,
  both;

  bool get canReceive => this == receiver || this == both;
  bool get canBroadcast => this == broadcaster || this == both;

  static NotificationMirrorMode fromName(String? value) {
    return NotificationMirrorMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => NotificationMirrorMode.off,
    );
  }
}

enum NotificationDetailMode {
  summary,
  full;

  static NotificationDetailMode fromName(String? value) {
    return NotificationDetailMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => NotificationDetailMode.full,
    );
  }
}

enum NotificationOverlayPosition {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight;

  bool get isTop => this == topLeft || this == topRight;
  bool get isLeft => this == topLeft || this == bottomLeft;

  static NotificationOverlayPosition fromName(String? value) {
    return NotificationOverlayPosition.values.firstWhere(
      (position) => position.name == value,
      orElse: () => NotificationOverlayPosition.bottomRight,
    );
  }
}

class ObservedNotificationApp {
  final String packageName;
  final String label;

  const ObservedNotificationApp({
    required this.packageName,
    required this.label,
  });
}

class NotificationMirrorController extends ChangeNotifier {
  NotificationMirrorController({
    NotificationMirrorSendFn? sendFn,
    Random? random,
  }) : _sendFn = sendFn,
       _random = random ?? Random.secure();

  static final instance = NotificationMirrorController();

  static const _kMode = 'notification_mirror_mode';
  static const _kAllowedPackages = 'notification_mirror_allowed_packages';
  static const _kMaxVisible = 'notification_mirror_max_visible';
  static const _kDurationSeconds = 'notification_mirror_duration_seconds';
  static const _kIgnoreOngoing = 'notification_mirror_ignore_ongoing';
  static const _kIgnoreSilent = 'notification_mirror_ignore_silent';
  static const _kAllowRepeat = 'notification_mirror_allow_repeat';
  static const _kReceiverToken = 'notification_mirror_receiver_token';
  static const _kBroadcastUrl = 'notification_mirror_broadcast_url';
  static const _kBroadcastToken = 'notification_mirror_broadcast_token';
  static const _kBroadcastAvailable = 'notification_mirror_broadcast_available';
  static const _kDetailMode = 'notification_mirror_detail_mode';
  static const _kSizeScale = 'notification_mirror_size_scale';
  static const _kOpacity = 'notification_mirror_opacity';
  static const _kPosition = 'notification_mirror_position';
  static const _kStreamEnabled = 'notification_mirror_stream_enabled';
  static const _kAuthorizedReceivers =
      'notification_mirror_authorized_receivers';
  static const _kPairedBroadcasters = 'notification_mirror_paired_broadcasters';

  final NotificationMirrorSendFn? _sendFn;
  final Random _random;
  final List<MirroredNotification> _visible = [];
  final Map<String, Timer> _timers = {};
  final Map<String, ObservedNotificationApp> _observedApps = {};
  final Map<String, NotificationPairRequest> _pendingPairRequests = {};
  final Map<String, NotificationPairStatus> _pairStatusByRequestId = {};
  final Map<String, AuthorizedNotificationReceiver> _authorizedReceivers = {};
  final Map<String, PairedNotificationBroadcaster> _pairedBroadcasters = {};
  final Set<String> _seen = {};

  StreamSubscription<MirroredNotification>? _platformSub;
  NotificationMirrorPlatform? _platform;
  bool _loaded = false;
  bool _notificationAccessGranted = false;
  NotificationMirrorMode _mode = NotificationMirrorMode.off;
  Set<String> _allowedPackages = {};
  int _maxVisible = 3;
  Duration _overlayDuration = const Duration(seconds: 8);
  bool _ignoreOngoing = true;
  bool _ignoreSilent = true;
  bool _allowRepeatNotifications = false;
  String _receiverToken = '';
  String _broadcastReceiverUrl = '';
  String _broadcastToken = '';
  bool _broadcastAvailable = false;
  NotificationDetailMode _detailMode = NotificationDetailMode.full;
  double _sizeScale = 1.0;
  double _opacity = 0.86;
  NotificationOverlayPosition _position =
      NotificationOverlayPosition.bottomRight;
  bool _streamEnabled = true;

  bool get loaded => _loaded;
  bool get notificationAccessGranted => _notificationAccessGranted;
  NotificationMirrorMode get mode => _mode;
  Set<String> get allowedPackages => Set.unmodifiable(_allowedPackages);
  int get maxVisible => _maxVisible;
  Duration get overlayDuration => _overlayDuration;
  bool get ignoreOngoing => _ignoreOngoing;
  bool get ignoreSilent => _ignoreSilent;
  bool get allowRepeatNotifications => _allowRepeatNotifications;
  String get receiverToken => _receiverToken;
  String get broadcastReceiverUrl => _broadcastReceiverUrl;
  String get broadcastToken => _broadcastToken;
  bool get broadcastAvailable => _broadcastAvailable;
  NotificationDetailMode get detailMode => _detailMode;
  double get sizeScale => _sizeScale;
  double get opacity => _opacity;
  NotificationOverlayPosition get position => _position;
  bool get streamEnabled => _streamEnabled;
  List<NotificationPairRequest> get pendingPairRequests {
    final list = _pendingPairRequests.values.toList()
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    return list;
  }

  List<AuthorizedNotificationReceiver> get authorizedReceivers {
    final list = _authorizedReceivers.values.toList()
      ..sort((a, b) => a.receiverName.compareTo(b.receiverName));
    return list;
  }

  List<PairedNotificationBroadcaster> get pairedBroadcasters {
    final list = _pairedBroadcasters.values.toList()
      ..sort((a, b) => a.deviceName.compareTo(b.deviceName));
    return list;
  }

  List<MirroredNotification> get visibleNotifications =>
      List.unmodifiable(_visible);
  List<ObservedNotificationApp> get observedApps {
    final list = _observedApps.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return list;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = NotificationMirrorMode.fromName(prefs.getString(_kMode));
    _allowedPackages = prefs.getStringList(_kAllowedPackages)?.toSet() ?? {};
    _maxVisible = (prefs.getInt(_kMaxVisible) ?? 3).clamp(1, 6);
    _overlayDuration = Duration(
      seconds: (prefs.getInt(_kDurationSeconds) ?? 8).clamp(2, 30),
    );
    _ignoreOngoing = prefs.getBool(_kIgnoreOngoing) ?? true;
    _ignoreSilent = prefs.getBool(_kIgnoreSilent) ?? true;
    _allowRepeatNotifications = prefs.getBool(_kAllowRepeat) ?? false;
    _receiverToken = prefs.getString(_kReceiverToken) ?? '';
    if (_receiverToken.isEmpty) {
      _receiverToken = _generateToken();
      await prefs.setString(_kReceiverToken, _receiverToken);
    }
    _broadcastReceiverUrl = prefs.getString(_kBroadcastUrl) ?? '';
    _broadcastToken = prefs.getString(_kBroadcastToken) ?? '';
    _broadcastAvailable = prefs.getBool(_kBroadcastAvailable) ?? false;
    _detailMode = NotificationDetailMode.fromName(
      prefs.getString(_kDetailMode),
    );
    _sizeScale = (prefs.getDouble(_kSizeScale) ?? 1.0).clamp(0.50, 2.0);
    _opacity = (prefs.getDouble(_kOpacity) ?? 0.86).clamp(0.20, 1.00);
    _position = NotificationOverlayPosition.fromName(
      prefs.getString(_kPosition),
    );
    _streamEnabled = prefs.getBool(_kStreamEnabled) ?? true;
    _loadAuthorizedReceivers(prefs);
    _loadPairedBroadcasters(prefs);
    _loaded = true;
    notifyListeners();
  }

  void attachPlatform(NotificationMirrorPlatform platform) {
    _platform = platform;
    _platformSub?.cancel();
    _platformSub = platform.notifications.listen(handleLocalPosted);
    unawaited(refreshNotificationAccess());
    unawaited(refreshInstalledApps());
  }

  Future<void> refreshNotificationAccess() async {
    final platform = _platform;
    final granted = platform == null
        ? false
        : await platform.isNotificationAccessGranted();
    if (_notificationAccessGranted == granted) return;
    _notificationAccessGranted = granted;
    notifyListeners();
  }

  Future<void> openNotificationAccessSettings() async {
    await _platform?.openNotificationAccessSettings();
  }

  Future<void> refreshInstalledApps() async {
    final platform = _platform;
    if (platform == null) return;
    final apps = await platform.getInstalledApps();
    var changed = false;
    for (final app in apps) {
      final packageName = (app['packageName'] ?? '').trim();
      if (packageName.isEmpty) continue;
      final label = (app['label'] ?? '').trim();
      final next = ObservedNotificationApp(
        packageName: packageName,
        label: label.isEmpty ? packageName : label,
      );
      final existing = _observedApps[packageName];
      if (existing?.label == next.label) continue;
      _observedApps[packageName] = next;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<void> setMode(NotificationMirrorMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMode, mode.name);
  }

  Future<void> setAllowedPackage(String packageName, bool allowed) async {
    if (allowed) {
      _allowedPackages.add(packageName);
    } else {
      _allowedPackages.remove(packageName);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kAllowedPackages,
      _allowedPackages.toList()..sort(),
    );
  }

  Future<void> setMaxVisible(int value) async {
    _maxVisible = value.clamp(1, 6);
    while (_visible.length > _maxVisible) {
      final removed = _visible.removeAt(0);
      _timers.remove(removed.dedupKey)?.cancel();
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMaxVisible, _maxVisible);
  }

  Future<void> setOverlayDuration(Duration duration) async {
    final seconds = duration.inSeconds.clamp(2, 30);
    _overlayDuration = Duration(seconds: seconds);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDurationSeconds, seconds);
  }

  Future<void> setIgnoreOngoing(bool value) async {
    _ignoreOngoing = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIgnoreOngoing, value);
  }

  Future<void> setIgnoreSilent(bool value) async {
    _ignoreSilent = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIgnoreSilent, value);
  }

  /// When OFF (default), an identical notification (same [stableKey]) is shown
  /// only once — re-posts with a refreshed timestamp are suppressed so banners
  /// don't re-appear like reminders. When ON, re-posts re-show.
  Future<void> setAllowRepeatNotifications(bool value) async {
    if (_allowRepeatNotifications == value) return;
    _allowRepeatNotifications = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAllowRepeat, value);
  }

  Future<void> setBroadcastTarget({
    required String receiverUrl,
    required String token,
  }) async {
    _broadcastReceiverUrl = receiverUrl.trim();
    _broadcastToken = token.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBroadcastUrl, _broadcastReceiverUrl);
    await prefs.setString(_kBroadcastToken, _broadcastToken);
  }

  Future<void> setBroadcastAvailable(bool value) async {
    _broadcastAvailable = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBroadcastAvailable, value);
  }

  Future<void> setDetailMode(NotificationDetailMode value) async {
    _detailMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDetailMode, value.name);
  }

  Future<void> setSizeScale(double value) async {
    _sizeScale = value.clamp(0.50, 2.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kSizeScale, _sizeScale);
  }

  Future<void> setOpacity(double value) async {
    _opacity = value.clamp(0.20, 1.00);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kOpacity, _opacity);
  }

  Future<void> setPosition(NotificationOverlayPosition value) async {
    _position = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPosition, value.name);
  }

  Future<void> setStreamEnabled(bool value) async {
    _streamEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kStreamEnabled, value);
  }

  NotificationPairRequest receivePairRequest({
    required String receiverDeviceId,
    required String receiverName,
    required String receiverUrl,
    required String receiverToken,
  }) {
    final existing = _authorizedReceivers[receiverDeviceId];
    final requestId = _makePairRequestId(receiverDeviceId);
    if (existing != null) {
      _pairStatusByRequestId[requestId] = NotificationPairStatus.accepted;
      return NotificationPairRequest(
        requestId: requestId,
        receiverDeviceId: receiverDeviceId,
        receiverName: existing.receiverName,
        receiverUrl: existing.receiverUrl,
        receiverToken: existing.receiverToken,
        status: NotificationPairStatus.accepted,
        requestedAt: DateTime.now().toUtc(),
      );
    }

    final request = NotificationPairRequest(
      requestId: requestId,
      receiverDeviceId: receiverDeviceId,
      receiverName: receiverName,
      receiverUrl: receiverUrl,
      receiverToken: receiverToken,
      status: NotificationPairStatus.pending,
      requestedAt: DateTime.now().toUtc(),
    );
    _pendingPairRequests[requestId] = request;
    _pairStatusByRequestId[requestId] = NotificationPairStatus.pending;
    notifyListeners();
    return request;
  }

  Future<void> acceptPairRequest(String requestId) async {
    final request = _pendingPairRequests.remove(requestId);
    if (request == null) return;
    _authorizedReceivers[request.receiverDeviceId] =
        AuthorizedNotificationReceiver(
          receiverDeviceId: request.receiverDeviceId,
          receiverName: request.receiverName,
          receiverUrl: request.receiverUrl,
          receiverToken: request.receiverToken,
          acceptedAt: DateTime.now().toUtc(),
        );
    _pairStatusByRequestId[requestId] = NotificationPairStatus.accepted;
    notifyListeners();
    await _saveAuthorizedReceivers();
  }

  void denyPairRequest(String requestId) {
    final request = _pendingPairRequests.remove(requestId);
    if (request == null) return;
    _pairStatusByRequestId[requestId] = NotificationPairStatus.denied;
    notifyListeners();
  }

  NotificationPairStatus pairRequestStatus(String requestId) {
    return _pairStatusByRequestId[requestId] ?? NotificationPairStatus.denied;
  }

  Future<void> removeAuthorizedReceiver(String receiverDeviceId) async {
    _authorizedReceivers.remove(receiverDeviceId);
    notifyListeners();
    await _saveAuthorizedReceivers();
  }

  Future<void> addPairedBroadcaster({
    required String deviceId,
    required String deviceName,
    required String url,
  }) async {
    _pairedBroadcasters[deviceId] = PairedNotificationBroadcaster(
      deviceId: deviceId,
      deviceName: deviceName,
      url: url,
      acceptedAt: DateTime.now().toUtc(),
    );
    notifyListeners();
    await _savePairedBroadcasters();
  }

  Future<void> removePairedBroadcaster(String deviceId) async {
    _pairedBroadcasters.remove(deviceId);
    notifyListeners();
    await _savePairedBroadcasters();
  }

  void handleLocalPosted(MirroredNotification notification) {
    _rememberObservedApp(notification);
    final normalized = _normalizeLocal(notification);
    if (!_shouldAccept(normalized, requireAllowlist: true)) return;
    if (_mode.canReceive) _show(normalized);
    if (_mode.canBroadcast) unawaited(_broadcast(normalized));
  }

  void handleRemotePosted(MirroredNotification notification) {
    _rememberObservedApp(notification);
    if (!_mode.canReceive) return;
    if (!_shouldAccept(notification, requireAllowlist: false)) return;
    _show(notification);
  }

  void dismiss(String dedupKey) {
    _timers.remove(dedupKey)?.cancel();
    _visible.removeWhere((notification) => notification.dedupKey == dedupKey);
    notifyListeners();
  }

  bool acceptsToken(String token) {
    return token.trim().isNotEmpty && token.trim() == _receiverToken;
  }

  bool _shouldAccept(
    MirroredNotification notification, {
    required bool requireAllowlist,
  }) {
    if (_mode == NotificationMirrorMode.off) return false;
    if (!notification.hasVisibleContent) return false;
    if (notification.isGroupSummary) return false;
    if (_ignoreOngoing && notification.isOngoing) return false;
    if (_ignoreSilent && notification.isSilent) return false;
    if (requireAllowlist &&
        !_allowedPackages.contains(notification.packageName)) {
      return false;
    }
    return true;
  }

  void _show(MirroredNotification notification) {
    // Default: dedup on the stable identity (no timestamp) so an app re-posting
    // the same notification doesn't re-show it like a reminder. When the user
    // opts into repeats, fall back to the timestamp-inclusive key so genuine
    // re-posts are treated as new and re-appear.
    final seenKey = _allowRepeatNotifications
        ? notification.dedupKey
        : notification.stableKey;
    if (_seen.contains(seenKey)) return;
    _seen.add(seenKey);
    _visible.removeWhere((item) => item.dedupKey == notification.dedupKey);
    _visible.add(notification);
    while (_visible.length > _maxVisible) {
      final removed = _visible.removeAt(0);
      _timers.remove(removed.dedupKey)?.cancel();
    }
    _timers[notification.dedupKey]?.cancel();
    _timers[notification.dedupKey] = Timer(_overlayDuration, () {
      dismiss(notification.dedupKey);
    });
    notifyListeners();
  }

  Future<void> _broadcast(MirroredNotification notification) async {
    final receivers = authorizedReceivers;
    if (receivers.isEmpty) {
      if (_broadcastReceiverUrl.isEmpty || _broadcastToken.isEmpty) return;
      await NotificationMirrorSender.send(
        notification: notification,
        receiverUrl: _broadcastReceiverUrl,
        token: _broadcastToken,
      );
      return;
    }

    for (final receiver in receivers) {
      final send = _sendFn;
      if (send != null) {
        await send(notification);
        continue;
      }
      await NotificationMirrorSender.send(
        notification: notification,
        receiverUrl: receiver.receiverUrl,
        token: receiver.receiverToken,
      );
    }
  }

  void _loadAuthorizedReceivers(SharedPreferences prefs) {
    _authorizedReceivers.clear();
    final raw = prefs.getStringList(_kAuthorizedReceivers) ?? const [];
    for (final item in raw) {
      try {
        final receiver = AuthorizedNotificationReceiver.fromJson(
          jsonDecode(item) as Map<String, dynamic>,
        );
        if (receiver.receiverDeviceId.isNotEmpty) {
          _authorizedReceivers[receiver.receiverDeviceId] = receiver;
        }
      } catch (_) {}
    }
  }

  void _loadPairedBroadcasters(SharedPreferences prefs) {
    _pairedBroadcasters.clear();
    final raw = prefs.getStringList(_kPairedBroadcasters) ?? const [];
    for (final item in raw) {
      try {
        final broadcaster = PairedNotificationBroadcaster.fromJson(
          jsonDecode(item) as Map<String, dynamic>,
        );
        if (broadcaster.deviceId.isNotEmpty) {
          _pairedBroadcasters[broadcaster.deviceId] = broadcaster;
        }
      } catch (_) {}
    }
  }

  Future<void> _saveAuthorizedReceivers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kAuthorizedReceivers,
      authorizedReceivers
          .map((receiver) => jsonEncode(receiver.toJson()))
          .toList(),
    );
  }

  Future<void> _savePairedBroadcasters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kPairedBroadcasters,
      pairedBroadcasters
          .map((broadcaster) => jsonEncode(broadcaster.toJson()))
          .toList(),
    );
  }

  String _makePairRequestId(String receiverDeviceId) {
    final id = receiverDeviceId.trim().isEmpty
        ? _generateToken()
        : receiverDeviceId;
    return '$id-${DateTime.now().toUtc().millisecondsSinceEpoch}';
  }

  MirroredNotification _normalizeLocal(MirroredNotification notification) {
    final sourceId = notification.sourceDeviceId.isNotEmpty
        ? notification.sourceDeviceId
        : ClientIdentity.uniqueId;
    return notification.copyWith(
      sourceDeviceId: sourceId,
      sourceDeviceName: notification.sourceDeviceName.isNotEmpty
          ? notification.sourceDeviceName
          : 'This device',
    );
  }

  void _rememberObservedApp(MirroredNotification notification) {
    if (notification.packageName.isEmpty) return;
    _observedApps[notification.packageName] = ObservedNotificationApp(
      packageName: notification.packageName,
      label: notification.appLabel.isNotEmpty
          ? notification.appLabel
          : notification.packageName,
    );
    notifyListeners();
  }

  String _generateToken() {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(
      32,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
  }

  @override
  void dispose() {
    _platformSub?.cancel();
    for (final timer in _timers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
