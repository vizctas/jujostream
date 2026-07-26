import 'package:shared_preferences/shared_preferences.dart';

/// Device-local visibility preferences, isolated per streaming host.
class HiddenAppsStore {
  const HiddenAppsStore();

  static String _key(String hostId) => 'hidden_apps_v1_$hostId';

  Future<Set<int>> load(String hostId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key(hostId)) ?? const <String>[])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
  }

  Future<void> save(String hostId, Set<int> appIds) async {
    final prefs = await SharedPreferences.getInstance();
    final values = appIds.map((id) => id.toString()).toList()..sort();
    await prefs.setStringList(_key(hostId), values);
  }
}
