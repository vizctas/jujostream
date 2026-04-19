import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_version.dart';
import '../../providers/locale_provider.dart';
import '../../providers/theme_provider.dart';

String _tr(BuildContext context, String en, String es) {
  return AppLocalizations.of(context).locale.languageCode == 'es' ? es : en;
}

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  static const _kofiUrl = 'https://ko-fi.com/jujodev';
  static const _repoUrl = 'https://github.com/vizctas/jujo.client';
  static const _artemisUrl = 'https://github.com/ClassicOldSong/moonlight-android';
  static const _moonlightUrl = 'https://github.com/moonlight-stream/moonlight-android';
  static const _licenseUrl = 'https://www.gnu.org/licenses/gpl-3.0.html';

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tp = context.watch<ThemeProvider>();
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.gameButtonB ||
            key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack) {
          Navigator.maybePop(context);
          return KeyEventResult.handled;
        }

        if (key == LogicalKeyboardKey.gameButtonLeft2) {
          if (_scrollController.hasClients && _scrollController.offset > 0) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
            );
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Scaffold(
        backgroundColor: tp.background,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: tp.colors.isLight ? Colors.black87 : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(
          shadows: [Shadow(color: Colors.black45, blurRadius: 8)],
        ),
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 0, bottom: 48),
        children: [

          _buildHeroHeader(context),
          const SizedBox(height: 8),

          _section(l.credits),
          _creditTile(
            icon: Icons.code,
            iconColor: context.read<ThemeProvider>().accentLight,
            title: l.developedBy,
            subtitle: 'Vizctas',
          ),
          _creditTile(
            icon: Icons.fork_right,
            iconColor: const Color(0xFF0F3460),
            title: l.basedOn,
            subtitle: 'ClassicOldSong (Artemis)',
          ),
          _linkTile(
            context: context,
            icon: Icons.fork_right,
            iconColor: const Color(0xFF0F3460),
            label: 'Artemis / moonlight-android',
            url: AboutScreen._artemisUrl,
          ),
          _linkTile(
            context: context,
            icon: Icons.fork_right,
            iconColor: Colors.white38,
            label: 'Moonlight Android (upstream)',
            url: AboutScreen._moonlightUrl,
          ),

          _section(_tr(context, 'Links', 'Enlaces')),
          _linkTile(
            context: context,
            icon: Icons.code,
            iconColor: context.read<ThemeProvider>().accentLight,
            label: _tr(context, 'Source Code (GitHub)', 'Código fuente (GitHub)'),
            url: AboutScreen._repoUrl,
          ),

          _section(_tr(context, 'License', 'Licencia')),
          _creditTile(
            icon: Icons.gavel,
            iconColor: Colors.white54,
            title: _tr(context, 'This project is open source', 'Este proyecto es open source'),
            subtitle: 'GNU General Public License v3.0',
          ),
          _linkTile(
            context: context,
            icon: Icons.open_in_new,
            iconColor: Colors.white38,
            label: _tr(context, 'Read the full license', 'Leer la licencia completa'),
            subtitle: 'gnu.org/licenses/gpl-3.0',
            url: AboutScreen._licenseUrl,
          ),
        ],
      ),
      ),
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;
    final topPadding = media.padding.top + kToolbarHeight + (isLandscape ? 16 : 24);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, topPadding, 24, isLandscape ? 20 : 30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tp.background,
            Color.lerp(tp.background, tp.accent, 0.62)!,
          ],
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            width: isLandscape ? 72 : 88,
            height: isLandscape ? 72 : 88,
            child: Image.asset(
              'assets/images/UI/logo/circular_dialog/circle_logo.png',
              fit: BoxFit.contain,
            ),
          ),
          SizedBox(height: isLandscape ? 12 : 16),
          Text(
            'JUJO Stream',
            style: TextStyle(
              color: Colors.white,
              fontSize: isLandscape ? 22 : 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _tr(context, 'Next-gen GameStream client for Sunshine & Apollo', 'Cliente GameStream de nueva generación para Sunshine y Apollo'),
            style: TextStyle(color: Colors.white54, fontSize: isLandscape ? 12 : 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              const _HeroStaticChip(label: kAppVersionDisplay),
              const _HeroStaticChip(label: 'GPL-3.0'),
            ],
          ),
          const SizedBox(height: 20),
          Focus(
            autofocus: false,
            onKeyEvent: (_, ev) {
              if (ev is! KeyDownEvent) return KeyEventResult.ignored;
              if (ev.logicalKey == LogicalKeyboardKey.enter ||
                  ev.logicalKey == LogicalKeyboardKey.select ||
                  ev.logicalKey == LogicalKeyboardKey.gameButtonA) {
                _launch(context, AboutScreen._kofiUrl);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (ctx) {
                final focused = Focus.of(ctx).hasFocus;
                return GestureDetector(
                  onTap: () => _launch(context, AboutScreen._kofiUrl),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: focused ? [
                        BoxShadow(
                          color: const Color(0xFF29abe0).withValues(alpha: 0.6),
                          blurRadius: 16,
                          spreadRadius: 4,
                        )
                      ] : [],
                      border: focused ? Border.all(color: Colors.white, width: 2) : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        'https://storage.ko-fi.com/cdn/kofi2.png?v=3',
                        height: 40,
                        errorBuilder: (_, _, _) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          color: const Color(0xFF29abe0),
                          child: const Text('Support me on Ko-fi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguagePicker(BuildContext context, AppLocalizations l) {
    final localeProvider = context.watch<LocaleProvider>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.language, color: Colors.white54),
          const SizedBox(width: 12),
          Expanded(
            child: Text(l.language,
                style: const TextStyle(color: Colors.white, fontSize: 16)),
          ),

          _langChip(
            context: context,
            code: 'en',
            label: 'English',
            active: localeProvider.locale.languageCode == 'en',
          ),
          const SizedBox(width: 8),

          _langChip(
            context: context,
            code: 'es',
            label: 'Español',
            active: localeProvider.locale.languageCode == 'es',
          ),
        ],
      ),
    );
  }

  Widget _langChip({
    required BuildContext context,
    required String code,
    required String label,
    required bool active,
    bool autofocus = false,
  }) {
    return _LangChip(
      code: code,
      label: label,
      active: active,
      autofocus: autofocus,
    );
  }

  Widget _section(String title) {
    final tp = context.read<ThemeProvider>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: tp.accent,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }

  Widget _creditTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return _FocusableStaticTile(
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        subtitle: Text(subtitle,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _linkTile({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String url,
    String? subtitle,
  }) {
    return _LinkTile(
      icon: icon,
      iconColor: iconColor,
      label: label,
      subtitle: subtitle,
      url: url,
      onLaunch: (u) => _launch(context, u),
    );
  }

  Future<void> _launch(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_tr(context, 'Could not open $url', 'No se pudo abrir $url'))),
        );
      }
    }
  }
}

class _LangChip extends StatefulWidget {
  final String code;
  final String label;
  final bool active;
  final bool autofocus;

  const _LangChip({
    required this.code,
    required this.label,
    required this.active,
    this.autofocus = false,
  });

  @override
  State<_LangChip> createState() => _LangChipState();
}

class _LangChipState extends State<_LangChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.1,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.gameButtonA) {
          context.read<LocaleProvider>().setByLanguageCode(widget.code);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () => context.read<LocaleProvider>().setByLanguageCode(widget.code),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: widget.active
                ? context.read<ThemeProvider>().accent
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _focused
                  ? Colors.white
                  : (widget.active ? context.read<ThemeProvider>().accent : Colors.white24),
              width: _focused ? 1.5 : 1.0,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: _focused || widget.active ? Colors.white : Colors.white54,
              fontWeight: widget.active ? FontWeight.w700 : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkTile extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final String url;
  final void Function(String) onLaunch;

  const _LinkTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.subtitle,
    required this.url,
    required this.onLaunch,
  });

  @override
  State<_LinkTile> createState() => _LinkTileState();
}

class _LinkTileState extends State<_LinkTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.15,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.gameButtonA) {
          widget.onLaunch(widget.url);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _focused ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _focused ? context.read<ThemeProvider>().accentLight : Colors.transparent,
            width: _focused ? 1.5 : 1.0,
          ),
        ),
        child: ListTile(
          leading: Icon(widget.icon, color: widget.iconColor),
          title: Text(widget.label, style: const TextStyle(color: Colors.white)),          subtitle: widget.subtitle != null
              ? Text(widget.subtitle!, style: const TextStyle(color: Colors.white54, fontSize: 12))
              : null,          trailing: const Icon(Icons.open_in_new, color: Colors.white38, size: 18),
          onTap: () => widget.onLaunch(widget.url),
        ),
      ),
    );
  }
}

class _HeroStaticChip extends StatelessWidget {
  final String label;

  const _HeroStaticChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.35,
        ),
      ),
    );
  }
}

class _HeroLinkChip extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final String url;
  final void Function(String) onLaunch;
  final Color accentColor;

  const _HeroLinkChip({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.url,
    required this.onLaunch,
    required this.accentColor,
  });

  @override
  State<_HeroLinkChip> createState() => _HeroLinkChipState();
}

class _HeroLinkChipState extends State<_HeroLinkChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.05,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.gameButtonA) {
          widget.onLaunch(widget.url);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () => widget.onLaunch(widget.url),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: _focused
                ? widget.accentColor.withValues(alpha: 0.26)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _focused ? Colors.white : Colors.white24,
              width: _focused ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: widget.iconColor, size: 14),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusableStaticTile extends StatefulWidget {
  final Widget child;
  const _FocusableStaticTile({required this.child});

  @override
  State<_FocusableStaticTile> createState() => _FocusableStaticTileState();
}

class _FocusableStaticTileState extends State<_FocusableStaticTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.15,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _focused ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _focused ? context.read<ThemeProvider>().accentLight : Colors.transparent,
            width: _focused ? 1.5 : 1.0,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
