import 'package:flutter/material.dart';
import '../models/nv_app.dart';

enum LauncherThemeId { classic, backbone, ps5, hero, bigScreen }

abstract class LauncherTheme {
  LauncherThemeId get id;

  String name(BuildContext context);

  String description(BuildContext context);

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
  });

  PreferredSizeWidget? buildAppBar({
    required BuildContext context,
    required String serverName,
    required String? activeSessionAppName,
    required VoidCallback onSettings,
    required VoidCallback onProfile,
    required VoidCallback onSearch,
    required VoidCallback onToggleView,
    required bool isGridView,
  }) => null;

  bool get hasSideMenu => false;

  Widget? buildSideMenu({
    required BuildContext context,
    required int selectedMenuIndex,
    required ValueChanged<int> onMenuChanged,
  }) => null;

  bool get hasStatusBar => false;

  Widget? buildStatusBar({required BuildContext context}) => null;
}
