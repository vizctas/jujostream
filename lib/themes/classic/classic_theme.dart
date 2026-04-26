import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/nv_app.dart';
import '../launcher_theme.dart';

class ClassicTheme extends LauncherTheme {
  @override
  LauncherThemeId get id => LauncherThemeId.classic;

  @override
  String name(BuildContext context) {
    final l = AppLocalizations.of(context);
    return l.launcherThemeClassic;
  }

  @override
  String description(BuildContext context) {
    final l = AppLocalizations.of(context);
    return l.launcherThemeClassicDesc;
  }

  @override
  Widget buildBody({
    required BuildContext context,
    required List<NvApp> apps,
    required List<NvApp> allApps,
    required int selectedIndex,
    required ValueChanged<NvApp> onAppSelected,
    required ValueChanged<NvApp> onAppDetails,
    required ValueChanged<int> onIndexChanged,
    required String? activeSessionAppId,
    required bool isGridView,
    required Set<String> favoriteIds,
    required ValueChanged<NvApp> onToggleFavorite,
    VoidCallback? onToggleView,
    Widget? videoWidget,
    int? videoForAppId,
    VoidCallback? onSearch,
    VoidCallback? onFilter,
    VoidCallback? onSmartFilters,
    VoidCallback? onResumeRunning,
    ValueChanged<bool>? onDetailViewChanged,
    String? activeFilterLabel,
  }) {
    return const SizedBox.shrink();
  }
}
