import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/computer_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/plugins_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/companion/companion_server.dart';
import '../../services/preferences/launcher_preferences.dart';
import '../../services/tv/tv_detector.dart';

class CompanionQrScreen extends StatefulWidget {
  const CompanionQrScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CompanionQrScreen()));
  }

  @override
  State<CompanionQrScreen> createState() => _CompanionQrScreenState();
}

class _CompanionQrScreenState extends State<CompanionQrScreen>
    with SingleTickerProviderStateMixin {
  String? _url;
  bool _loading = true;
  String? _errorType;
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _startServer();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _startServer() async {
    try {
      final plugins = context.read<PluginsProvider>();
      await CompanionServer.instance.start(
        plugins,
        settingsProvider: context.read<SettingsProvider>(),
        localeProvider: context.read<LocaleProvider>(),
        themeProvider: context.read<ThemeProvider>(),
        launcherPreferences: context.read<LauncherPreferences>(),
        computerProvider: context.read<ComputerProvider>(),
      );
      final url = await CompanionServer.instance.lanUrl;
      if (!mounted) return;
      setState(() {
        _url = url;
        _loading = false;
        _errorType = url == null ? 'no_ip' : null;
      });
      if (url != null) _fadeCtrl.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorType = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final isTV = TvDetector.instance.isTV;
    final scale = isTV ? 1.3 : 1.0;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.gameButtonB ||
            key == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          _scrollController.animateTo(
            (_scrollController.offset + 80).clamp(
              0.0,
              _scrollController.position.maxScrollExtent,
            ),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          _scrollController.animateTo(
            (_scrollController.offset - 80).clamp(
              0.0,
              _scrollController.position.maxScrollExtent,
            ),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: tp.background,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: tp.colors.isLight ? Colors.black87 : Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            AppLocalizations.of(context).configureFromPhone,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 17 * scale,
              letterSpacing: -0.3,
            ),
          ),
        ),
        body: Center(
          child: _loading
              ? _buildLoading(tp, scale)
              : _errorType != null
                  ? _buildError(tp, scale)
                  : FadeTransition(
                      opacity: _fadeAnim,
                      child: _buildQrContent(tp, scale),
                    ),
        ),
      ),
    );
  }

  Widget _buildLoading(ThemeProvider tp, double scale) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 28 * scale,
          height: 28 * scale,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: tp.accent,
          ),
        ),
        SizedBox(height: 16 * scale),
        Text(
          'Starting server...',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 13 * scale,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildError(ThemeProvider tp, double scale) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.all(32 * scale),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64 * scale,
            height: 64 * scale,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.redAccent.withValues(alpha: 0.12),
            ),
            child: Icon(
              Icons.wifi_off_rounded,
              color: Colors.redAccent,
              size: 28 * scale,
            ),
          ),
          SizedBox(height: 20 * scale),
          Text(
            _errorType == 'no_ip'
                ? l.noLocalIpError
                : l.serverStartError(_errorType!),
            style: TextStyle(
              color: Colors.white60,
              fontSize: 14 * scale,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 28 * scale),
          _ActionButton(
            label: l.retry,
            icon: Icons.refresh_rounded,
            accent: tp.accent,
            onTap: () {
              setState(() {
                _loading = true;
                _errorType = null;
              });
              _startServer();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQrContent(ThemeProvider tp, double scale) {
    final l = AppLocalizations.of(context);
    final safePadding = MediaQuery.paddingOf(context);
    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        28 * scale,
        safePadding.top + kToolbarHeight + 16 * scale,
        28 * scale,
        32 * scale,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52 * scale,
            height: 52 * scale,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tp.accent.withValues(alpha: 0.12),
            ),
            child: Icon(
              Icons.phone_android_rounded,
              color: tp.accentLight,
              size: 24 * scale,
            ),
          ),
          SizedBox(height: 18 * scale),
          Text(
            l.scanQrInstruction,
            style: TextStyle(
              color: tp.colors.isLight ? Colors.black87 : Colors.white,
              fontSize: 20 * scale,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8 * scale),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 340 * scale),
            child: Text(
              l.qrDescription,
              style: TextStyle(
                color: tp.colors.isLight ? Colors.black45 : Colors.white54,
                fontSize: 13 * scale,
                height: 1.55,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 28 * scale),

          Container(
            padding: EdgeInsets.all(18 * scale),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(
              data: _url!,
              version: QrVersions.auto,
              size: 190 * scale,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF1A1A2E),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
          SizedBox(height: 18 * scale),

          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 18 * scale,
              vertical: 10 * scale,
            ),
            decoration: BoxDecoration(
              color: tp.surfaceVariant.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.link_rounded,
                  color: tp.accentLight,
                  size: 16 * scale,
                ),
                SizedBox(width: 8 * scale),
                Flexible(
                  child: SelectableText(
                    _url!,
                    style: TextStyle(
                      color: tp.accentLight,
                      fontSize: 14 * scale,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 28 * scale),

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6 * scale,
                height: 6 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.greenAccent.withValues(alpha: 0.7),
                ),
              ),
              SizedBox(width: 8 * scale),
              Text(
                l.serverActiveNote,
                style: TextStyle(
                  color: tp.colors.isLight ? Colors.black38 : Colors.white38,
                  fontSize: 11 * scale,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.gameButtonA ||
            event.logicalKey == LogicalKeyboardKey.select) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: _focused
                ? widget.accent
                : widget.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                color: _focused ? Colors.white : widget.accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: _focused ? Colors.white : widget.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
