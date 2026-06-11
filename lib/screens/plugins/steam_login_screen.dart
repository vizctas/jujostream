import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../providers/theme_provider.dart';

class SteamLoginResult {
  final String steamId;
  final String? apiKey;
  final List<int> ownedAppIds;

  const SteamLoginResult({
    required this.steamId,
    this.apiKey,
    this.ownedAppIds = const [],
  });

  bool get hasApiKey => apiKey != null && apiKey!.isNotEmpty;
  bool get hasFallbackAppIds => ownedAppIds.isNotEmpty;
}

enum _Phase { login, apiKey, ownedApps, done }

class SteamLoginScreen extends StatefulWidget {
  const SteamLoginScreen({super.key});

  static Future<SteamLoginResult?> show(BuildContext context) {
    return Navigator.push<SteamLoginResult>(
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
  _Phase _phase = _Phase.login;
  String? _extractedSteamId;
  Timer? _timeoutTimer;
  int _apiKeyAttempts = 0;

  static const String _loginUrl = 'https://steamcommunity.com/login/home/';
  static const String _apiKeyUrl =
      'https://steamcommunity.com/dev/apikey?l=english';
  static const String _dynamicStoreUrl =
      'https://store.steampowered.com/dynamicstore/userdata/';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/124.0.0.0 Safari/537.36',
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (url) {
          if (mounted) setState(() => _loading = false);
          _onPageFinished(url);
        },
        onNavigationRequest: (request) => NavigationDecision.navigate,
      ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.loadRequest(Uri.parse(_loginUrl));
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _onPageFinished(String url) {
    switch (_phase) {
      case _Phase.login:
        _tryExtractSteamId(url);
      case _Phase.apiKey:
        if (url.contains('dev/apikey')) {
          _tryExtractApiKey();
        } else if (url.contains('/login/')) {
          // Steam redirected back to login — skip key, fall through to owned-apps
          _fallbackToOwnedApps();
        }
      case _Phase.ownedApps:
        if (url.contains('dynamicstore/userdata')) { _tryExtractOwnedApps(); }
      case _Phase.done:
        break;
    }
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
            _extractedSteamId = id;
            _phase = _Phase.apiKey;
            _apiKeyAttempts = 0;
            // Overall timeout for the post-login scraping phases
            _timeoutTimer?.cancel();
            _timeoutTimer = Timer(const Duration(seconds: 30), () {
              if (_phase != _Phase.done && _extractedSteamId != null) {
                _popWithResult(SteamLoginResult(steamId: _extractedSteamId!));
              }
            });
            _controller.loadRequest(Uri.parse(_apiKeyUrl));
          }
        })
        .catchError((_) {});
  }

  void _tryExtractApiKey() {
    _apiKeyAttempts++;
    if (_apiKeyAttempts > 2) {
      _fallbackToOwnedApps();
      return;
    }

    _controller
        .runJavaScriptReturningResult(r'''
          (function(){
            var keyMatch = document.body.innerText.match(/Key:\s*([0-9A-F]{32})/i);
            if (keyMatch) return keyMatch[1];
            var domainInput = document.getElementById('Domain') ||
                              document.querySelector('input[name="Domain"]');
            if (domainInput) {
              domainInput.value = 'localhost';
              var checkboxes = document.querySelectorAll('input[type="checkbox"]');
              checkboxes.forEach(function(cb){ if(!cb.checked) cb.click(); });
              var form = document.querySelector('form');
              if (form) { form.submit(); return 'submitting'; }
            }
            return '';
          })()
        ''')
        .then(
          (result) {
            final value = result.toString().replaceAll('"', '').trim();
            if (RegExp(r'^[0-9A-F]{32}$', caseSensitive: false).hasMatch(value)) {
              _popWithResult(SteamLoginResult(
                steamId: _extractedSteamId!,
                apiKey: value.toUpperCase(),
              ));
            } else if (value == 'submitting') {
              // Form submitted; wait for onPageFinished to fire again after redirect
            } else {
              _fallbackToOwnedApps();
            }
          },
          onError: (_) => _fallbackToOwnedApps(),
        );
  }

  void _fallbackToOwnedApps() {
    if (_phase == _Phase.done) return;
    _phase = _Phase.ownedApps;
    _controller.loadRequest(Uri.parse(_dynamicStoreUrl));
  }

  void _tryExtractOwnedApps() {
    _controller
        .runJavaScriptReturningResult(r'''
          (function(){
            var fromWindow = window.g_rgOwnedApps || [];
            if (Array.isArray(fromWindow) && fromWindow.length > 0)
              return JSON.stringify(fromWindow);
            var text = document.body ? document.body.innerText : '';
            if (!text) return '[]';
            try {
              var parsed = JSON.parse(text);
              return JSON.stringify(parsed.rgOwnedApps || []);
            } catch(e) { return '[]'; }
          })()
        ''')
        .then((result) {
          // Strip outer quotes that webview_flutter adds to JS string return values
          var raw = result.toString().trim();
          if (raw.startsWith('"') && raw.endsWith('"')) {
            raw = raw.substring(1, raw.length - 1);
          }
          raw = raw.replaceAll('[', '').replaceAll(']', '');
          final appIds = raw
              .split(',')
              .where((s) => s.trim().isNotEmpty)
              .map((s) => int.tryParse(s.trim()))
              .whereType<int>()
              .toList();
          _popWithResult(SteamLoginResult(
            steamId: _extractedSteamId!,
            ownedAppIds: appIds,
          ));
        },
        onError: (_) {
          _popWithResult(SteamLoginResult(steamId: _extractedSteamId!));
        });
  }

  void _popWithResult(SteamLoginResult result) {
    if (_phase == _Phase.done) return;
    _phase = _Phase.done;
    _timeoutTimer?.cancel();
    if (mounted) Navigator.pop(context, result);
  }

  String get _phaseTitle {
    switch (_phase) {
      case _Phase.login:
        return 'Conectar con Steam';
      case _Phase.apiKey:
        return 'Obteniendo clave...';
      case _Phase.ownedApps:
        return 'Leyendo biblioteca...';
      case _Phase.done:
        return 'Conectado';
    }
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
          title: Text(_phaseTitle),
          actions: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white54,
                  ),
                ),
              ),
          ],
        ),
        body: WebViewWidget(controller: _controller),
      ),
    );
  }
}
