import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  static const _kLocaleKey = 'app_locale';

  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  static Future<LocaleProvider> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kLocaleKey);
    final provider = LocaleProvider();
    if (code != null && ['en', 'es'].contains(code)) {
      provider._locale = Locale(code);
    }
    return provider;
  }

  Future<void> setLocale(Locale locale) async {
    if (locale == _locale) return;
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocaleKey, locale.languageCode);
  }

  Future<void> setByLanguageCode(String code) => setLocale(Locale(code));
}
