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
    // `selected` arrives from the closure of whichever card's FocusNode really
    // holds Flutter focus. The highlight the user sees follows _selectedAppId
    // instead, and _requestCardFocus is best-effort — when it misses (node not
    // built after a long jump or a filter switch), the two desync and pressing
    // A launched a different game than the highlighted one. Every action below
    // resolves against the same state that paints the highlight.
    selected = _selectedApp(apps);
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final logical = event.logicalKey;

    // Only the LB/RB tab-switch branches need the category list, but it was
    // computed up front — four full-library passes on EVERY keypress, arrows
    // included. Held D-pad repeat paid it dozens of times per second.
    List<_CategoryItem>? categoriesCache;
    List<_CategoryItem> categories() {
      if (categoriesCache != null) return categoriesCache!;
      final cats = _categoryItems(
        context.read<AppListProvider>().apps.toList(),
      );
      if (_selectedCategoryIndex >= cats.length) {
        _selectedCategoryIndex = 0;
      }
      return categoriesCache = cats;
    }

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
      final cats = categories();
      int nextIdx = _selectedCategoryIndex;
      for (int i = 0; i < cats.length; i++) {
        nextIdx = (nextIdx + 1) % cats.length;
        if (cats[nextIdx].count > 0) break;
      }
      _feedbackNavigate();
      setState(() => _selectedCategoryIndex = nextIdx);
      _applyFilter(
        cats[nextIdx].filter,
        playniteCategory: cats[nextIdx].playniteCategory,
        collectionId: cats[nextIdx].collectionId,
      );
      return KeyEventResult.handled;
    }

    if (logical == LogicalKeyboardKey.gameButtonLeft2) {
      final cats = categories();
      int nextIdx = _selectedCategoryIndex;
      for (int i = 0; i < cats.length; i++) {
        nextIdx = (nextIdx - 1 + cats.length) % cats.length;
        if (cats[nextIdx].count > 0) break;
      }
      _feedbackNavigate();
      setState(() => _selectedCategoryIndex = nextIdx);
      _applyFilter(
        cats[nextIdx].filter,
        playniteCategory: cats[nextIdx].playniteCategory,
        collectionId: cats[nextIdx].collectionId,
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
