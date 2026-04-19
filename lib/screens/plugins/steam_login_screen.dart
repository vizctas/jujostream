import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../providers/theme_provider.dart';

class SteamLoginScreen extends StatefulWidget {
  const SteamLoginScreen({super.key});

  static Future<String?> show(BuildContext context) {
    return Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const SteamLoginScreen()),
    );
  }

  @override
  State<SteamLoginScreen> createState() => _SteamLoginScreenState();
}

class _SteamLoginScreenState extends State<SteamLoginScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  static const String _loginUrl = 'https://steamcommunity.com/login/home/';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)

      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 12; Pixel 6) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (url) {
          if (mounted) setState(() => _loading = false);
          _tryExtractSteamId(url);
        },
        onNavigationRequest: (request) => NavigationDecision.navigate,
      ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.loadRequest(Uri.parse(_loginUrl));
    });
  }

  void _tryExtractSteamId(String url) {
    if (!url.contains('steamcommunity.com')) return;

    if (url.contains('/login/') || url.contains('/openid/')) return;

    _controller
        .runJavaScriptReturningResult(
          r'''(function(){
            if(typeof g_steamID !== "undefined" && /^\d{17}$/.test(g_steamID))
              return g_steamID;
            var m=window.location.href.match(/\/profiles\/(\d{17})/);
            if(m) return m[1];
            return "";
          })()''',
        )
        .then((result) {
          final id = result.toString().replaceAll('"', '').trim();
          if (id.length == 17 && RegExp(r'^\d+$').hasMatch(id)) {
            if (mounted) Navigator.pop(context, id);
          }
        })
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
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
        return KeyEventResult.ignored;
      },
      child: Scaffold(
      backgroundColor: context.read<ThemeProvider>().background,
      appBar: AppBar(
        backgroundColor: context.read<ThemeProvider>().surface,
        foregroundColor: Colors.white,
        title: const Text('Conectar con Steam'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
              ),
            ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
      ),
    );
  }
}
