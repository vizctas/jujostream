import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LauncherPreferences extends ChangeNotifier {

  double _backgroundBlur = 0.0;
  double _backgroundDim = 0.28;

  double _cardBorderRadius = 16.0;
  double _cardSpacing = 15.0;
  double _cardWidth = 170.0;
  double _cardHeight = 140.0;
  bool _showCardLabels = true;
  bool _showRunningBadge = true;

  bool _showCategoryBar = true;
  bool _showCategoryCounts = true;

  bool _enableParallaxDrift = true;
  double _parallaxSpeed = 20.0;

  bool _searchActivatesOnType = false;

  int _maxRecentCount = 8;

  bool _showButtonHints = true;
  String _buttonScheme = 'xbox';

  bool _desktopFullscreen = true;

  String _profileId = 'classic';
  String _key(String base) => '${_profileId}_$base';

  void switchProfile(String profileId) async {
    _profileId = profileId;
    await load();
  }

  double get backgroundBlur => _backgroundBlur;
  double get backgroundDim => _backgroundDim;
  double get cardBorderRadius => _cardBorderRadius;
  double get cardSpacing => _cardSpacing;
  double get cardWidth => _cardWidth;
  double get cardHeight => _cardHeight;
  bool get showCardLabels => _showCardLabels;
  bool get showRunningBadge => _showRunningBadge;
  bool get showCategoryBar => _showCategoryBar;
  bool get showCategoryCounts => _showCategoryCounts;
  bool get enableParallaxDrift => _enableParallaxDrift;
  double get parallaxSpeed => _parallaxSpeed;
  bool get searchActivatesOnType => _searchActivatesOnType;
  int get maxRecentCount => _maxRecentCount;
  bool get showButtonHints => _showButtonHints;
  String get buttonScheme => _buttonScheme;
  bool get desktopFullscreen => _desktopFullscreen;

  Future<void> load([String? profileId]) async {
    if (profileId != null) _profileId = profileId;
    final p = await SharedPreferences.getInstance();

    double getD(String k, double def) => p.getDouble(_key(k)) ?? def;
    bool getB(String k, bool def) => p.getBool(_key(k)) ?? def;
    int getI(String k, int def) => p.getInt(_key(k)) ?? def;
    String getS(String k, String def) => p.getString(_key(k)) ?? def;

    // Classic profile defaults: blur=0, radius=16, spacing=18, w=126, h=170
    final isClassic = _profileId == 'classic';
    _backgroundBlur = getD('lp_bgBlur', isClassic ? 0.0 : 1.0);
    _backgroundDim = getD('lp_bgDim', 0.28);
    _cardBorderRadius = getD('lp_cardRadius', isClassic ? 16.0 : 7.0);
    _cardSpacing = getD('lp_cardSpacing', isClassic ? 15.0 : 10.0);
    _cardWidth = getD('lp_cardWidth', isClassic ? 170.0 : 156.0);
    _cardHeight = getD('lp_cardHeight', isClassic ? 140.0 : 214.0);
    _showCardLabels = getB('lp_cardLabels', true);
    _showRunningBadge = getB('lp_runningBadge', true);
    _showCategoryBar = getB('lp_categoryBar', true);
    _showCategoryCounts = getB('lp_categoryCounts', true);
    _enableParallaxDrift = getB('lp_parallax', true);
    _parallaxSpeed = getD('lp_parallaxSpeed', 20.0);
    _searchActivatesOnType = getB('lp_searchOnType', false);
    _maxRecentCount = getI('lp_maxRecentCount', 8).clamp(1, 12);
    _showButtonHints = getB('lp_showButtonHints', true);
    _buttonScheme = getS('lp_buttonScheme', 'xbox');
    _desktopFullscreen = getB('lp_desktopFullscreen', true);
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setDouble(_key('lp_bgBlur'), _backgroundBlur),
      p.setDouble(_key('lp_bgDim'), _backgroundDim),
      p.setDouble(_key('lp_cardRadius'), _cardBorderRadius),
      p.setDouble(_key('lp_cardSpacing'), _cardSpacing),
      p.setDouble(_key('lp_cardWidth'), _cardWidth),
      p.setDouble(_key('lp_cardHeight'), _cardHeight),
      p.setBool(_key('lp_cardLabels'), _showCardLabels),
      p.setBool(_key('lp_runningBadge'), _showRunningBadge),
      p.setBool(_key('lp_categoryBar'), _showCategoryBar),
      p.setBool(_key('lp_categoryCounts'), _showCategoryCounts),
      p.setBool(_key('lp_parallax'), _enableParallaxDrift),
      p.setDouble(_key('lp_parallaxSpeed'), _parallaxSpeed),
      p.setBool(_key('lp_searchOnType'), _searchActivatesOnType),
      p.setInt(_key('lp_maxRecentCount'), _maxRecentCount),
      p.setBool(_key('lp_showButtonHints'), _showButtonHints),
      p.setString(_key('lp_buttonScheme'), _buttonScheme),
      p.setBool(_key('lp_desktopFullscreen'), _desktopFullscreen),
    ]);
  }

  void setBackgroundBlur(double v) {
    _backgroundBlur = v.clamp(0, 30);
    notifyListeners();
    _save();
  }

  void setBackgroundDim(double v) {
    _backgroundDim = v.clamp(0, 0.85);
    notifyListeners();
    _save();
  }

  void setCardBorderRadius(double v) {
    _cardBorderRadius = v.clamp(0, 28);
    notifyListeners();
    _save();
  }

  void setCardSpacing(double v) {
    _cardSpacing = v.clamp(2, 28);
    notifyListeners();
    _save();
  }

  void setCardWidth(double v) {
    _cardWidth = v.clamp(100, 240);
    notifyListeners();
    _save();
  }

  void setCardHeight(double v) {
    _cardHeight = v.clamp(140, 320);
    notifyListeners();
    _save();
  }

  void setShowCardLabels(bool v) {
    _showCardLabels = v;
    notifyListeners();
    _save();
  }

  void setShowRunningBadge(bool v) {
    _showRunningBadge = v;
    notifyListeners();
    _save();
  }

  void setShowCategoryBar(bool v) {
    _showCategoryBar = v;
    notifyListeners();
    _save();
  }

  void setShowCategoryCounts(bool v) {
    _showCategoryCounts = v;
    notifyListeners();
    _save();
  }

  void setEnableParallaxDrift(bool v) {
    _enableParallaxDrift = v;
    notifyListeners();
    _save();
  }

  void setParallaxSpeed(double v) {
    _parallaxSpeed = v.clamp(4, 60);
    notifyListeners();
    _save();
  }

  void setSearchActivatesOnType(bool v) {
    _searchActivatesOnType = v;
    notifyListeners();
    _save();
  }

  void setMaxRecentCount(int v) {
    _maxRecentCount = v.clamp(1, 12);
    notifyListeners();
    _save();
  }

  void setShowButtonHints(bool v) {
    _showButtonHints = v;
    notifyListeners();
    _save();
  }

  void setButtonScheme(String v) {
    _buttonScheme = v;
    notifyListeners();
    _save();
  }

  void setDesktopFullscreen(bool v) {
    _desktopFullscreen = v;
    notifyListeners();
    _save();
  }

  Future<void> resetDefaults() async {
    final isClassic = _profileId == 'classic';
    _backgroundBlur = isClassic ? 0.0 : 1.0;
    _backgroundDim = 0.28;
    _cardBorderRadius = isClassic ? 16.0 : 7.0;
    _cardSpacing = isClassic ? 15.0 : 10.0;
    _cardWidth = isClassic ? 170.0 : 156.0;
    _cardHeight = isClassic ? 140.0 : 214.0;
    _showCardLabels = true;
    _showRunningBadge = true;
    _showCategoryBar = true;
    _showCategoryCounts = true;
    _enableParallaxDrift = true;
    _parallaxSpeed = 20.0;
    _searchActivatesOnType = false;
    _maxRecentCount = 8;
    _showButtonHints = true;
    _buttonScheme = 'xbox';
    _desktopFullscreen = true;
    notifyListeners();
    await _save();
  }
}
