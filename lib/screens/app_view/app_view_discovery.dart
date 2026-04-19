part of 'app_view_screen.dart';

mixin _AppViewDiscoveryMixin on _AppViewScreenBase {
  List<NvApp> _computeSimilarGames(NvApp selected, List<NvApp> allApps) {
    if (selected.metadataGenres.isEmpty) return const [];
    final selectedGenres = selected.metadataGenres.toSet();

    final minScore = selectedGenres.length <= 2 ? selectedGenres.length : 2;

    final scored =
        allApps
            .where(
              (a) => a.appId != selected.appId && a.metadataGenres.isNotEmpty,
            )
            .map(
              (a) => (
                app: a,
                score: a.metadataGenres
                    .toSet()
                    .intersection(selectedGenres)
                    .length,
              ),
            )
            .where((e) => e.score >= minScore)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    return scored.take(8).map((e) => e.app).toList();
  }

  @override
  Widget _buildDiscoveryBoostSection(NvApp selected, List<NvApp> allApps) {
    final pluginsProvider = context.read<PluginsProvider>();
    if (!pluginsProvider.canUseDiscoveryBoost) return const SizedBox.shrink();
    final similar = _computeSimilarGames(selected, allApps);
    if (similar.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.explore_outlined,
                  color: Colors.cyanAccent,
                  size: 15,
                ),
                const SizedBox(width: 5),
                Text(
                  'Similar a este',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 76,
            child: ListView.separated(
              controller: _discoveryController,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: similar.length,
              separatorBuilder: (_, _) => const SizedBox(width: 7),
              itemBuilder: (_, i) => _buildDiscoveryThumb(similar[i], allApps),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoveryThumb(NvApp app, List<NvApp> allApps) {
    final isSelected = app.appId == _selectedAppId;
    return GestureDetector(
      onTap: () {
        _feedbackNavigate();

        var visibleApps = _visibleApps(allApps);
        int idx = visibleApps.indexWhere((a) => a.appId == app.appId);
        if (idx < 0) {
          setState(() {
            _activeFilter = _AppFilter.all;
            _activePlayniteCategory = null;
            _activeMacroGenre = null;
          });
          visibleApps = _visibleApps(allApps);
          idx = visibleApps.indexWhere((a) => a.appId == app.appId);
        }
        setState(() {
          _selectedAppId = app.appId;
          _focusedAppId = app.appId;
        });
        _queueAccentColorExtraction(app);
        _requestCardFocus(app.appId);
        if (idx >= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _centerOnIndex(idx, visibleApps.length);
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 50,
        height: 68,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: isSelected
                ? (_accentColor ?? _tp.accentLight)
                : Colors.white12,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (_accentColor ?? _tp.accentLight).withValues(
                      alpha: 0.4,
                    ),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: app.posterUrl != null
              ? PosterImage(
                  url: app.posterUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const _DiscoveryPlaceholder(),
                )
              : const _DiscoveryPlaceholder(),
        ),
      ),
    );
  }
}

class _DiscoveryPlaceholder extends StatelessWidget {
  const _DiscoveryPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white12,
    child: const Icon(
      Icons.videogame_asset_outlined,
      color: Colors.white24,
      size: 20,
    ),
  );
}
