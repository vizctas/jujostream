import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'startup_animation_registry.dart';

class StartupAnimationPreferences extends ChangeNotifier {
  static const storageKey = 'startup_animation_id';

  StartupAnimationPreferences._(this._storedId);

  String? _storedId;

  static Future<StartupAnimationPreferences> load() async {
    final preferences = await SharedPreferences.getInstance();
    return StartupAnimationPreferences._(preferences.getString(storageKey));
  }

  String get selectedId => StartupAnimationRegistry.resolve(_storedId).id;

  StartupAnimationDefinition get selected =>
      StartupAnimationRegistry.resolve(_storedId);

  Future<void> setSelectedId(String id) async {
    if (!StartupAnimationRegistry.supports(id)) {
      throw ArgumentError.value(id, 'id', 'Unsupported startup animation');
    }
    if (_storedId == id) return;

    _storedId = id;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(storageKey, id);
  }
}
