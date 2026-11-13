import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/gaming_news_item.dart';
import '../../models/nv_app.dart';
import '../../providers/theme_provider.dart';
import '../../services/audio/ui_sound_service.dart';
import '../../services/tv/tv_detector.dart';
import '../poster_image.dart';

class _ReaderAction {
  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onActivate;

  const _ReaderAction({
    required this.label,
    required this.icon,
    required this.onActivate,
    this.primary = false,
  });
}

/// Gamepad-first modal reader for a [GamingNewsItem].
class GamingNewsReaderDialog extends StatefulWidget {
  final GamingNewsItem item;
  final List<NvApp> allApps;
  final ValueChanged<NvApp>? onPlayApp;
  final ValueChanged<NvApp>? onAppDetails;

  const GamingNewsReaderDialog({
    super.key,
    required this.item,
    required this.allApps,
    this.onPlayApp,
    this.onAppDetails,
  });

  static Future<void> show(
    BuildContext context, {
    required GamingNewsItem item,
    required List<NvApp> allApps,
    ValueChanged<NvApp>? onPlayApp,
    ValueChanged<NvApp>? onAppDetails,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (_) => GamingNewsReaderDialog(
        item: item,
        allApps: allApps,
        onPlayApp: onPlayApp,
        onAppDetails: onAppDetails,
      ),
    );
  }

  @override
  State<GamingNewsReaderDialog> createState() => _GamingNewsReaderDialogState();
}

class _GamingNewsReaderDialogState extends State<GamingNewsReaderDialog> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'news_reader_dialog');
  int _selectedIdx = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  NvApp? get _linkedApp {
    final relatedId = widget.item.relatedAppId;
    if (relatedId == null || relatedId <= 0) return null;
    for (final app in widget.allApps) {
      if (app.steamAppId == relatedId) return app;
    }
    return null;
  }

  Future<void> _openExternalSource(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  List<_ReaderAction> _buildActions(AppLocalizations l) {
    final linked = _linkedApp;
    final sourceUrl = widget.item.sourceUrl;
    return [
      if (linked != null && widget.onPlayApp != null)
        _ReaderAction(
          label: l.play,
          icon: Icons.play_arrow_rounded,
          primary: true,
          onActivate: () {
            Navigator.pop(context);
            widget.onPlayApp!(linked);
          },
        ),
      if (linked != null && widget.onAppDetails != null)
        _ReaderAction(
          label: l.details,
          icon: Icons.info_outline_rounded,
          onActivate: () {
            Navigator.pop(context);
            widget.onAppDetails!(linked);
          },
        ),
      if (sourceUrl != null && sourceUrl.isNotEmpty)
        _ReaderAction(
          label: l.openArticleSource,
          icon: Icons.open_in_new_rounded,
          primary: linked == null,
          onActivate: () {
            unawaited(_openExternalSource(sourceUrl));
          },
        ),
      _ReaderAction(
        label: l.close,
        icon: Icons.close_rounded,
        onActivate: () => Navigator.pop(context),
      ),
    ];
  }

  void _navFeedback() {
    UiSoundService.playClick();
    if (!TvDetector.instance.isTV) HapticFeedback.lightImpact();
  }

  KeyEventResult _handleKey(
    FocusNode node,
    KeyEvent event,
    List<_ReaderAction> actions,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.gameButtonB ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      _navFeedback();
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft && actions.isNotEmpty) {
      _navFeedback();
      setState(
        () => _selectedIdx = (_selectedIdx - 1).clamp(0, actions.length - 1),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight && actions.isNotEmpty) {
      _navFeedback();
      setState(
        () => _selectedIdx = (_selectedIdx + 1).clamp(0, actions.length - 1),
      );
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select) &&
        actions.isNotEmpty) {
      UiSoundService.playClick();
      actions[_selectedIdx.clamp(0, actions.length - 1)].onActivate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final l = AppLocalizations.of(context);
    final actions = _buildActions(l);
    final safeIdx = actions.isEmpty ? 0 : _selectedIdx.clamp(0, actions.length - 1);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (n, e) => _handleKey(n, e, actions),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
          child: Material(
            color: tp.surface,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            elevation: 24,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildArtwork(tp),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0x22000000),
                                  Color(0xEE0D0F14),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 14,
                            left: 16,
                            right: 16,
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tp.accent.withValues(alpha: 0.90),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    widget.item.typeLabel,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.9,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (widget.item.dateLabel.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      widget.item.dateLabel,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.item.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          if (widget.item.subtitle.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              widget.item.subtitle,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 13.5,
                                height: 1.48,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (int i = 0; i < actions.length; i++)
                                _buildActionButton(
                                  actions[i],
                                  focused: i == safeIdx,
                                  tp: tp,
                                  onSelect: () => setState(() => _selectedIdx = i),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    _ReaderAction action, {
    required bool focused,
    required ThemeProvider tp,
    required VoidCallback onSelect,
  }) {
    final bg = focused
        ? tp.accent
        : action.primary
        ? tp.accent.withValues(alpha: 0.35)
        : Colors.white.withValues(alpha: 0.08);
    return GestureDetector(
      onTap: () {
        onSelect();
        action.onActivate();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: focused
                ? Colors.white.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.14),
            width: focused ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(action.icon, color: Colors.white, size: 17),
            const SizedBox(width: 7),
            Text(
              action.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtwork(ThemeProvider tp) {
    final linked = _linkedApp;
    if (linked != null &&
        linked.posterUrl != null &&
        linked.posterUrl!.isNotEmpty) {
      return PosterImage(
        url: linked.posterUrl!,
        cacheKey: linked.artCacheKey('poster'),
        fit: BoxFit.cover,
        memCacheWidth: 800,
        errorWidget: (_, _, _) => _buildExternalImage(tp),
      );
    }
    return _buildExternalImage(tp);
  }

  Widget _buildExternalImage(ThemeProvider tp) {
    final url = widget.item.imageUrl;
    if (url != null && url.isNotEmpty) {
      return PosterImage(
        url: url,
        fit: BoxFit.cover,
        memCacheWidth: 800,
        errorWidget: (_, _, _) => _fallbackArt(tp),
      );
    }
    return _fallbackArt(tp);
  }

  Widget _fallbackArt(ThemeProvider tp) {
    return Image.asset(
      'assets/images/news_placeholder.png',
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(color: tp.surfaceVariant),
    );
  }
}

