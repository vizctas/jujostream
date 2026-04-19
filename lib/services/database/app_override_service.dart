import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AppOverrideService {
  AppOverrideService._();
  static final instance = AppOverrideService._();

  static const _prefsKey = 'app_overrides_v1';

  final Map<String, AppOverride> _overrides = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_prefsKey);
    if (json != null) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        for (final entry in map.entries) {
          _overrides[entry.key] = AppOverride.fromJson(entry.value);
        }
      } catch (_) {

      }
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    for (final entry in _overrides.entries) {
      map[entry.key] = entry.value.toJson();
    }
    await prefs.setString(_prefsKey, jsonEncode(map));
  }

  String _key(String serverId, int appId) => '${serverId}_$appId';

  String? getCustomName(String serverId, int appId) {
    return _overrides[_key(serverId, appId)]?.customName;
  }

  String? getCustomPosterUrl(String serverId, int appId) {
    return _overrides[_key(serverId, appId)]?.customPosterUrl;
  }

  bool hasOverrides(String serverId, int appId) {
    final o = _overrides[_key(serverId, appId)];
    return o != null && (o.customName != null || o.customPosterUrl != null);
  }

  Future<void> setCustomName(String serverId, int appId, String? name) async {
    final key = _key(serverId, appId);
    final existing = _overrides[key] ?? const AppOverride();
    final updated = existing.copyWith(customName: name);
    if (updated.isEmpty) {
      _overrides.remove(key);
    } else {
      _overrides[key] = updated;
    }
    await _save();
  }

  Future<void> setCustomPosterUrl(String serverId, int appId, String? url) async {
    final key = _key(serverId, appId);
    final existing = _overrides[key] ?? const AppOverride();
    final updated = existing.copyWith(customPosterUrl: url);
    if (updated.isEmpty) {
      _overrides.remove(key);
    } else {
      _overrides[key] = updated;
    }
    await _save();
  }

  Future<void> clearOverrides(String serverId, int appId) async {
    _overrides.remove(_key(serverId, appId));
    await _save();
  }
}

class AppOverride {
  final String? customName;
  final String? customPosterUrl;

  const AppOverride({this.customName, this.customPosterUrl});

  bool get isEmpty => customName == null && customPosterUrl == null;

  AppOverride copyWith({String? customName, String? customPosterUrl}) {
    return AppOverride(
      customName: customName ?? this.customName,
      customPosterUrl: customPosterUrl ?? this.customPosterUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    if (customName != null) 'name': customName,
    if (customPosterUrl != null) 'poster': customPosterUrl,
  };

  factory AppOverride.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      return AppOverride(
        customName: json['name'] as String?,
        customPosterUrl: json['poster'] as String?,
      );
    }
    return const AppOverride();
  }
}
