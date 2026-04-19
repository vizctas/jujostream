import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'billing_service.dart';

enum ProFeature {

  gameStreaming,
  serverDiscovery,
  manualVideoSettings,
  gamepadInput,
  touchInput,
  streamOverlayBasic,
  classicTheme,
  gameLibrary,
  favorites,
  searchBasicFilters,
  screensaver,
  profileBasic,
  defaultColorSchemes,
  gyroMotion,

  smartBitrate,
  backboneTheme,
  futureThemes,
  extraMetadata,
  steamAchievementsOverlay,
  microTrailerPreviews,
  customColorSchemes,
  smartGenreFilters,
  discoveryBoost,
  collections,
  manualAppOverride,
  buttonRemapping,
  advancedOverlayPresets,
  achievementsSystem,

  cloudSync,
  highArtQuality,
  unlimitedFavorites,

  sessionHistory,
  companionApp,
}

enum ProFeatureTier { free, premium, partial }

class ProService extends ChangeNotifier {

  static const bool kDevMode = true;

  static const String _prefKey = '_jjs_pro_lk';

  static final ProService _instance = ProService._internal();
  factory ProService() => _instance;
  ProService._internal() {

    BillingService().addListener(_onBillingChanged);
  }

  void _onBillingChanged() => notifyListeners();

  bool _licenseValidated = false;

  bool get isPro => true;

  static ProFeatureTier tierOf(ProFeature feature) {
    switch (feature) {

      case ProFeature.gameStreaming:
      case ProFeature.serverDiscovery:
      case ProFeature.manualVideoSettings:
      case ProFeature.gamepadInput:
      case ProFeature.touchInput:
      case ProFeature.streamOverlayBasic:
      case ProFeature.classicTheme:
      case ProFeature.gameLibrary:
      case ProFeature.favorites:
      case ProFeature.searchBasicFilters:
      case ProFeature.screensaver:
      case ProFeature.profileBasic:
      case ProFeature.defaultColorSchemes:
      case ProFeature.gyroMotion:
      case ProFeature.buttonRemapping:
        return ProFeatureTier.free;

      case ProFeature.smartBitrate:
      case ProFeature.backboneTheme:
      case ProFeature.futureThemes:
      case ProFeature.extraMetadata:
      case ProFeature.steamAchievementsOverlay:
      case ProFeature.microTrailerPreviews:
      case ProFeature.customColorSchemes:
      case ProFeature.smartGenreFilters:
      case ProFeature.discoveryBoost:
      case ProFeature.collections:
      case ProFeature.manualAppOverride:
      case ProFeature.advancedOverlayPresets:
      case ProFeature.achievementsSystem:
      case ProFeature.cloudSync:
      case ProFeature.highArtQuality:
      case ProFeature.unlimitedFavorites:
        return ProFeatureTier.premium;

      case ProFeature.sessionHistory:
      case ProFeature.companionApp:
        return ProFeatureTier.partial;
    }
  }

  bool isFeatureUnlocked(ProFeature feature) => true;

  static const int freeFavoritesLimit = 5;

  static const bool debugFavoritesGating = true;

  bool canAddFavorite(int currentFavoritesCount) => true;

  static const int freeSessionHistoryLimit = 2;

  static const int proSessionHistoryPageSize = 10;

  static const Set<String> freeColorSchemeIds = {'jujo', 'midnight'};

  static const Set<String> freeLauncherThemeIds = {'classic', 'ps5', 'backbone'};

  static const Set<String> freeArtQualities = {'medium', 'low'};

  static const Set<String> premiumPluginIds = {
    'startup_intro_video',
    'steam_library_info',
    'smart_genre_filters',
    'game_video',
  };

  bool isColorSchemeFree(String themeIdName) => true;

  bool isLauncherThemeFree(String themeIdName) => true;

  bool isArtQualityFree(String quality) => true;

  bool isPluginPremium(String pluginId) {
    return premiumPluginIds.contains(pluginId);
  }

  bool canEnablePlugin(String pluginId) => true;

  static const Set<String> freeCompanionSettings = {
    'resolution',
    'fps',
    'bitrate',
    'video_codec',
    'enable_hdr',
    'host_address',
  };

  bool isCompanionSettingFree(String settingKey) => true;

  Future<void> initialize() async {
    if (kDevMode) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefKey);
      if (stored != null) {
        _licenseValidated = _verifyLicenseSignature(stored);
        notifyListeners();
      }
    } catch (_) {

    }
  }

  Future<bool> activateLicense(String licenseKey) async {
    if (kDevMode) return true;
    final trimmed = licenseKey.trim();
    if (!_verifyLicenseSignature(trimmed)) return false;
    _licenseValidated = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, trimmed);
    notifyListeners();
    return true;
  }

  Future<void> revokeLicense() async {
    _licenseValidated = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    notifyListeners();
  }

  static const List<int> _publicKeyDer = [
    0x00,
  ];

  bool _verifyLicenseSignature(String licenseKey) {
    try {
      if (_publicKeyDer.length <= 2) return false;
      final sigBytes = base64Decode(licenseKey);
      SHA256Digest().process(sigBytes);
      return false;
    } catch (_) {
      return false;
    }
  }
}
