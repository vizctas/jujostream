class MirroredNotification {
  final String id;
  final String sourceDeviceId;
  final String sourceDeviceName;
  final String packageName;
  final String appLabel;
  final String title;
  final String body;
  final DateTime postedAt;
  final bool isOngoing;
  final bool isSilent;
  final bool isGroupSummary;
  final String? icon;

  const MirroredNotification({
    required this.id,
    required this.sourceDeviceId,
    required this.sourceDeviceName,
    required this.packageName,
    required this.appLabel,
    required this.title,
    required this.body,
    required this.postedAt,
    required this.isOngoing,
    this.isSilent = false,
    this.isGroupSummary = false,
    this.icon,
  });

  String get dedupKey =>
      '$sourceDeviceId|$packageName|$id|${postedAt.millisecondsSinceEpoch}';

  /// Identity of a notification WITHOUT the posted timestamp. Apps frequently
  /// re-post the same notification (same package + id) with a refreshed
  /// timestamp; [dedupKey] changes each time, which would let the banner
  /// re-appear like a "reminder". [stableKey] stays constant across those
  /// re-posts so the controller can suppress repeats by default.
  String get stableKey => '$sourceDeviceId|$packageName|$id';

  bool get hasVisibleContent =>
      title.trim().isNotEmpty || body.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceDeviceId': sourceDeviceId,
    'sourceDeviceName': sourceDeviceName,
    'packageName': packageName,
    'appLabel': appLabel,
    'title': title,
    'body': body,
    'postedAt': postedAt.toUtc().toIso8601String(),
    'isOngoing': isOngoing,
    'isSilent': isSilent,
    'isGroupSummary': isGroupSummary,
    if (icon != null) 'icon': icon,
  };

  factory MirroredNotification.fromJson(Map<String, dynamic> json) {
    return MirroredNotification(
      id: (json['id'] ?? '').toString(),
      sourceDeviceId: (json['sourceDeviceId'] ?? '').toString(),
      sourceDeviceName: (json['sourceDeviceName'] ?? '').toString(),
      packageName: (json['packageName'] ?? '').toString(),
      appLabel: (json['appLabel'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      postedAt: _parsePostedAt(json['postedAt']),
      isOngoing: json['isOngoing'] == true,
      isSilent: json['isSilent'] == true,
      isGroupSummary: json['isGroupSummary'] == true,
      icon: json['icon']?.toString(),
    );
  }

  static DateTime _parsePostedAt(Object? value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  MirroredNotification copyWith({
    String? id,
    String? sourceDeviceId,
    String? sourceDeviceName,
    String? packageName,
    String? appLabel,
    String? title,
    String? body,
    DateTime? postedAt,
    bool? isOngoing,
    bool? isSilent,
    bool? isGroupSummary,
    String? icon,
  }) {
    return MirroredNotification(
      id: id ?? this.id,
      sourceDeviceId: sourceDeviceId ?? this.sourceDeviceId,
      sourceDeviceName: sourceDeviceName ?? this.sourceDeviceName,
      packageName: packageName ?? this.packageName,
      appLabel: appLabel ?? this.appLabel,
      title: title ?? this.title,
      body: body ?? this.body,
      postedAt: postedAt ?? this.postedAt,
      isOngoing: isOngoing ?? this.isOngoing,
      isSilent: isSilent ?? this.isSilent,
      isGroupSummary: isGroupSummary ?? this.isGroupSummary,
      icon: icon ?? this.icon,
    );
  }
}
