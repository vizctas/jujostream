part of 'app_view_screen.dart';

Future<void> _feedbackNavigate() async {
  UiSoundService.playClick();
  HapticFeedback.lightImpact();
}

Future<void> _feedbackAction() async {
  await HapticFeedback.mediumImpact();
}

Future<void> _feedbackHeavy() async {
  await HapticFeedback.heavyImpact();
}

mixin _AppViewGamepadMixin on _AppViewScreenBase {
  @override
  KeyEventResult _onKeyEvent(KeyEvent event, List<NvApp> apps, NvApp selected) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final allApps = context.read<AppListProvider>().apps.toList();
    final categories = _categoryItems(allApps);
    if (_selectedCategoryIndex >= categories.length) {
      _selectedCategoryIndex = 0;
    }

    final logical = event.logicalKey;

    if (logical == LogicalKeyboardKey.arrowRight) {
      _moveSelection(apps, 1);
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.arrowLeft) {
      _moveSelection(apps, -1);
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.arrowDown) {
      if (_viewMode == _ViewMode.grid) {
        final cols = _gridCrossAxisCount();
        _moveSelection(apps, cols);
      } else {

        if (_postersHidden) {
          _feedbackNavigate();
          setState(() => _postersHidden = false);
        } else if (!_showBottomFilterBar) {
          setState(() => _showBottomFilterBar = true);
        }
      }
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.arrowUp) {
      if (_viewMode == _ViewMode.grid) {
        final cols = _gridCrossAxisCount();
        _moveSelection(apps, -cols);
      } else {

        if (_showBottomFilterBar) {
          setState(() => _showBottomFilterBar = false);
        } else if (!_postersHidden) {
          _feedbackNavigate();
          setState(() => _postersHidden = true);
        }
      }
      return KeyEventResult.handled;
    }

    if (logical == LogicalKeyboardKey.enter ||
        logical == LogicalKeyboardKey.select ||
        logical == LogicalKeyboardKey.gameButtonA) {
      _handleAppTap(selected);
      return KeyEventResult.handled;
    }

    if (logical == LogicalKeyboardKey.escape ||
        logical == LogicalKeyboardKey.goBack ||
        logical == LogicalKeyboardKey.browserBack ||
        logical == LogicalKeyboardKey.gameButtonB) {
      Navigator.maybePop(context);
      return KeyEventResult.handled;
    }

    if (logical == LogicalKeyboardKey.gameButtonX) {
      _feedbackAction();
      setState(() {
        _viewMode = _viewMode == _ViewMode.carousel
            ? _ViewMode.grid
            : _ViewMode.carousel;
      });
      if (_viewMode == _ViewMode.grid) {
        _disposeVideoController();
      } else {
        _scheduleVideoPreview(selected);
      }
      return KeyEventResult.handled;
    }

    if (logical == LogicalKeyboardKey.gameButtonY) {
      _feedbackAction();
      _openDetailsScreen(selected);
      return KeyEventResult.handled;
    }

    if (logical == LogicalKeyboardKey.gameButtonStart) {
      _feedbackHeavy();
      final provider = context.read<AppListProvider>();
      if (apps.any((a) => a.isRunning)) {
        _confirmQuitApp(provider);
      } else {
        _launchApp(selected);
      }
      return KeyEventResult.handled;
    }

    if (logical == LogicalKeyboardKey.gameButtonSelect) {
      _feedbackAction();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AppViewPresentationSettingsScreen(
            preferences: context.read<LauncherPreferences>(),
          ),
        ),
      );
      return KeyEventResult.handled;
    }

    if (logical == LogicalKeyboardKey.gameButtonThumbLeft) {
      _feedbackAction();
      _openSearch();
      return KeyEventResult.handled;
    }

    if (logical == LogicalKeyboardKey.gameButtonThumbRight) {
      _feedbackAction();
      _openSmartGenreFilters();
      return KeyEventResult.handled;
    }

    if (logical == LogicalKeyboardKey.gameButtonRight2) {
      int nextIdx = _selectedCategoryIndex;
      for (int i = 0; i < categories.length; i++) {
        nextIdx = (nextIdx + 1) % categories.length;
        if (categories[nextIdx].count > 0) break;
      }
      _feedbackNavigate();
      setState(() => _selectedCategoryIndex = nextIdx);
      _applyFilter(
        categories[nextIdx].filter,
        playniteCategory: categories[nextIdx].playniteCategory,
        collectionId: categories[nextIdx].collectionId,
      );
      return KeyEventResult.handled;
    }

    if (logical == LogicalKeyboardKey.gameButtonLeft2) {
      int nextIdx = _selectedCategoryIndex;
      for (int i = 0; i < categories.length; i++) {
        nextIdx = (nextIdx - 1 + categories.length) % categories.length;
        if (categories[nextIdx].count > 0) break;
      }
      _feedbackNavigate();
      setState(() => _selectedCategoryIndex = nextIdx);
      _applyFilter(
        categories[nextIdx].filter,
        playniteCategory: categories[nextIdx].playniteCategory,
        collectionId: categories[nextIdx].collectionId,
      );
      return KeyEventResult.handled;
    }

    if (logical == LogicalKeyboardKey.gameButtonRight1) {
      _feedbackAction();
      _toggleFavorite(selected);
      return KeyEventResult.handled;
    }

    if (logical == LogicalKeyboardKey.keyM ||
        logical == LogicalKeyboardKey.contextMenu) {
      _showActionsSheet(apps, selected);
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.keyI) {
      _openDetailsScreen(selected);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  void _moveSelection(List<NvApp> apps, int delta) {
    if (apps.isEmpty) return;
    final currentIndex = apps.indexWhere((a) => a.appId == _selectedAppId);
    final start = currentIndex >= 0 ? currentIndex : 0;
    final next = (start + delta).clamp(0, apps.length - 1);
    if (next == start) return;
    final app = apps[next];
    _feedbackNavigate();
    setState(() {
      _selectedAppId = app.appId;
      _focusedAppId = app.appId;
    });
    _queueAccentColorExtraction(app);

    if (_viewMode == _ViewMode.grid) {
      _scrollGridToIndex(next);
    } else {
      _centerOnIndex(next, apps.length);
    }
    _requestCardFocus(app.appId);
  }

}
