import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/computer_details.dart';
import '../../providers/theme_provider.dart';

String _t(BuildContext ctx, String en, String es) {
  final loc = Localizations.localeOf(ctx);
  return loc.languageCode == 'es' ? es : en;
}

class _ApiAction {
  final String id;
  final String label;
  final String desc;
  final IconData icon;
  final String method;
  final String path;
  final bool showsLogs;
  final bool picksFile;
  final bool isDanger;
  final bool enabled;

  const _ApiAction({
    required this.id,
    required this.label,
    required this.desc,
    required this.icon,
    required this.method,
    required this.path,
    this.showsLogs = false,
    this.picksFile = false,
    this.isDanger = false,
    this.enabled = true,
  });
}

const _actions = <_ApiAction>[
  _ApiAction(
    id: 'logs',
    label: 'Server Logs',
    desc: 'Fetch recent session logs',
    icon: Icons.article_outlined,
    method: 'GET',
    path: '/api/logs',
    showsLogs: true,
  ),
  _ApiAction(
    id: 'restart',
    label: 'Restart',
    desc: 'Restart VibeApollo service',
    icon: Icons.restart_alt_rounded,
    method: 'POST',
    path: '/api/restart',
    isDanger: true,
  ),
  _ApiAction(
    id: 'force_sync',
    label: 'Playnite Sync',
    desc: 'Force Playnite library sync',
    icon: Icons.sync_rounded,
    method: 'POST',
    path: '/api/playnite/force_sync',
  ),
  _ApiAction(
    id: 'covers',
    label: 'Upload Cover',
    desc: 'Upload a cover image',
    icon: Icons.image_outlined,
    method: 'POST',
    path: '/api/covers/upload',
    picksFile: true,
    enabled: false,
  ),
  _ApiAction(
    id: 'disconnect',
    label: 'Disconnect All',
    desc: 'Disconnect active clients',
    icon: Icons.power_off_outlined,
    method: 'POST',
    path: '/api/clients/disconnect',
    isDanger: true,
  ),
  _ApiAction(
    id: 'unpair_all',
    label: 'Unpair All',
    desc: 'Remove all paired clients',
    icon: Icons.link_off_rounded,
    method: 'POST',
    path: '/api/clients/unpair-all',
    isDanger: true,
  ),
  _ApiAction(
    id: 'display',
    label: 'Display Devices',
    desc: 'List connected displays',
    icon: Icons.monitor_outlined,
    method: 'GET',
    path: '/api/display-devices',
  ),
  _ApiAction(
    id: 'update',
    label: 'Update Clients',
    desc: 'Push client configuration',
    icon: Icons.system_update_alt_rounded,
    method: 'POST',
    path: '/api/clients/update',
    enabled: false,
  ),
];

class VibeApolloScreen extends StatefulWidget {
  final ComputerDetails computer;
  const VibeApolloScreen({super.key, required this.computer});

  @override
  State<VibeApolloScreen> createState() => _VibeApolloScreenState();
}

class _VibeApolloScreenState extends State<VibeApolloScreen> {
  final _scrollCtrl = ScrollController();
  final _tokenCtrl = TextEditingController();
  final _mainFocus = FocusNode(debugLabel: 'va-main');

  String? _loadingId;
  bool _tokenVisible = false;
  bool _validating = false; // running token-test ping
  bool? _tokenOk; // null=untested  true=valid  false=invalid

  late String _prefKey;

  @override
  void initState() {
    super.initState();
    _prefKey = 'va_token_${widget.computer.uuid}';
    _loadToken();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _tokenCtrl.dispose();
    _mainFocus.dispose();
    super.dispose();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_prefKey) ?? '';
    if (t.isNotEmpty && mounted) setState(() => _tokenCtrl.text = t);
  }

  Future<void> _saveToken(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, v.trim());
    if (mounted) {
      setState(
        () => _tokenOk = null,
      ); // invalidate cached result on token change
    }
  }

  Future<void> _validateToken() async {
    final tk = _tokenCtrl.text.trim();
    if (tk.isEmpty) {
      _toast(
        _t(context, 'Enter an API token first.', 'Ingresa un token primero.'),
        ok: false,
      );
      return;
    }
    setState(() => _validating = true);
    final client = _buildClient();
    try {
      final uri = Uri.parse('$_baseUrl/api/display-devices');
      final response = await client
          .get(uri, headers: _authHeader)
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() => _tokenOk = true);
        _toast(_t(context, 'Token is valid ✔', 'Token válido ✔'));
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        setState(() => _tokenOk = false);
        _toast(
          _t(
            context,
            'Invalid token — check privileges.',
            'Token inválido — revisa los privilegios.',
          ),
          ok: false,
        );
      } else {
        setState(() => _tokenOk = false);
        _toast('HTTP ${response.statusCode}', ok: false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _tokenOk = false);
      _toast(
        _t(context, 'Cannot reach server.', 'No se pudo conectar al servidor.'),
        ok: false,
      );
    } finally {
      client.close();
      if (mounted) setState(() => _validating = false);
    }
  }

  http.Client _buildClient() {
    final inner = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..badCertificateCallback = (_, _, _) => true;
    return IOClient(inner);
  }

  String get _baseUrl {
    final addr = widget.computer.activeAddress.isNotEmpty
        ? widget.computer.activeAddress
        : widget.computer.localAddress;
    // derive web UI port from the external port (+1); default 47990
    final cfgPort = widget.computer.externalPort > 0
        ? widget.computer.externalPort + 1
        : 47990;
    return 'https://$addr:$cfgPort';
  }

  Map<String, String> get _authHeader {
    final tk = _tokenCtrl.text.trim();
    return tk.isNotEmpty ? {'Authorization': 'Bearer $tk'} : {};
  }

  String _decodeBody(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  void _toast(String msg, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: ok ? const Color(0xFF1C4A2E) : const Color(0xFF4A1C1C),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _exec(_ApiAction action) async {
    if (_loadingId != null) return;
    if (!action.enabled) return;

    final tk = _tokenCtrl.text.trim();
    if (tk.isEmpty) {
      _toast(
        _t(
          context,
          'No token set. Open the token row and paste your API token.',
          'Sin token. Abre la fila del token y pega tu Bearer token.',
        ),
        ok: false,
      );
      return;
    }

    if (action.picksFile) {
      await _execCoverUpload(action);
      return;
    }

    setState(() => _loadingId = action.id);
    final client = _buildClient();
    try {
      final uri = Uri.parse('$_baseUrl${action.path}');
      final response = action.method == 'GET'
          ? await client.get(uri, headers: _authHeader)
          : await client.post(uri, headers: _authHeader);

      final body = _decodeBody(response.bodyBytes);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (action.showsLogs) {
          _toast(_t(context, 'Logs loaded', 'Logs cargados'));
          await _showLogsDialog(
            body.isEmpty
                ? _t(context, '(no log data)', '(sin datos de log)')
                : body,
          );
        } else if (action.id == 'force_sync') {
          _toast(_t(context, 'Sync in progress', 'Sincronizacion en progreso'));
        } else {
          _toast(_prettyPreview(body, action));
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _toast(
          _t(
            context,
            'Not token generated with this privilege. Please create a valid token.',
            'Sin privilegio. Crea un token valido con este acceso.',
          ),
          ok: false,
        );
      } else {
        final snippet = body.length > 160 ? body.substring(0, 160) : body;
        _toast('HTTP ${response.statusCode}: $snippet', ok: false);
      }
    } catch (e) {
      final d = e.toString();
      _toast(
        '${_t(context, 'Connection error — check token and server.', 'Error de conexion — revisa token y servidor.')}\n${d.length > 80 ? d.substring(0, 80) : d}',
        ok: false,
      );
    } finally {
      client.close();
      if (mounted) setState(() => _loadingId = null);
    }
  }

  Future<void> _execCoverUpload(_ApiAction action) async {
    final pick = await FilePicker.pickFiles(type: FileType.image);
    if (pick == null || pick.files.isEmpty) return;
    final path = pick.files.single.path;
    if (path == null) return;

    setState(() => _loadingId = action.id);
    final client = _buildClient();
    try {
      final uri = Uri.parse('$_baseUrl${action.path}');
      final req = http.MultipartRequest('POST', uri)
        ..headers.addAll(_authHeader)
        ..files.add(await http.MultipartFile.fromPath('cover', path));

      final streamed = await client.send(req);
      final bytes = await streamed.stream.toBytes();
      final body = _decodeBody(bytes);

      if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
        _toast(_t(context, 'Cover uploaded', 'Portada subida'));
      } else if (streamed.statusCode == 401 || streamed.statusCode == 403) {
        _toast(
          _t(
            context,
            'Not token generated with this privilege. Please create a valid token.',
            'Sin privilegio. Crea un token valido.',
          ),
          ok: false,
        );
      } else {
        _toast('HTTP ${streamed.statusCode}: $body', ok: false);
      }
    } catch (e) {
      _toast('Upload failed: $e', ok: false);
    } finally {
      client.close();
      if (mounted) setState(() => _loadingId = null);
    }
  }

  String _prettyPreview(String body, _ApiAction action) {
    if (body.trim().isEmpty) return '${action.label} — OK';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map || decoded is List) {
        final s = const JsonEncoder.withIndent('  ').convert(decoded);
        return s.length > 300 ? s.substring(0, 300) : s;
      }
    } catch (_) {}
    return body.length > 200 ? body.substring(0, 200) : body;
  }

  Future<void> _showLogsDialog(String logs) async {
    final scrollCtrl = ScrollController();

    Future<void> scrollBy(double delta) async {
      if (!scrollCtrl.hasClients) return;
      final target = (scrollCtrl.offset + delta).clamp(
        0.0,
        scrollCtrl.position.maxScrollExtent,
      );
      await scrollCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    }

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        final tp = dialogContext.watch<ThemeProvider>();
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          child: Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final key = event.logicalKey;
              if (key == LogicalKeyboardKey.gameButtonB ||
                  key == LogicalKeyboardKey.escape ||
                  key == LogicalKeyboardKey.goBack) {
                Navigator.of(dialogContext).pop();
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowDown) {
                scrollBy(120);
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowUp) {
                scrollBy(-120);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Container(
              constraints: const BoxConstraints(maxWidth: 760, maxHeight: 560),
              decoration: BoxDecoration(
                color: tp.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 10, 10),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.article_outlined,
                            color: Colors.white70,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _t(
                                context,
                                'Server Logs',
                                'Registros del servidor',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _t(context, 'Copy', 'Copiar'),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: logs));
                              _toast(
                                _t(context, 'Logs copied', 'Logs copiados'),
                              );
                            },
                            icon: const Icon(
                              Icons.copy_rounded,
                              color: Colors.white60,
                              size: 18,
                            ),
                          ),
                          IconButton(
                            tooltip: _t(context, 'Close', 'Cerrar'),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white60,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                        child: SelectableText(
                          logs,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontFamily: 'monospace',
                            height: 1.55,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    scrollCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final size = MediaQuery.sizeOf(context);
    final wide = size.width > 700;

    return Focus(
      focusNode: _mainFocus,
      autofocus: true,
      onKeyEvent: (_, ev) {
        if (ev is! KeyDownEvent) return KeyEventResult.ignored;
        final k = ev.logicalKey;
        if (k == LogicalKeyboardKey.gameButtonB ||
            k == LogicalKeyboardKey.escape ||
            k == LogicalKeyboardKey.goBack) {
          Navigator.maybePop(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: tp.background,
        appBar: AppBar(
          backgroundColor: tp.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 2,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.dashboard_customize_outlined,
                size: 18,
                color: tp.accent,
              ),
              const SizedBox(width: 8),
              const Text(
                'VibeApollo',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
            ],
          ),
          foregroundColor: Colors.white,
        ),
        body: ListView(
          controller: _scrollCtrl,
          padding: EdgeInsets.symmetric(
            horizontal: wide ? size.width * 0.06 : 16,
            vertical: 12,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0, left: 4.0),
              child: Text(
                _t(context,
                  'In order to use these features, you must generate an API token on your host PC and provide it here.',
                  'Para usar estas funciones, debes generar un token de API en tu PC host y proporcionarlo aquí.'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            _buildTokenRow(tp),
            const SizedBox(height: 14),
            _sectionLabel(_t(context, 'Server', 'Servidor')),
            const SizedBox(height: 8),
            _buildGrid(
              tp,
              wide,
              _actions
                  .where((a) => a.id == 'restart' || a.id == 'logs')
                  .toList(),
            ),
            const SizedBox(height: 18),
            _sectionLabel(_t(context, 'Clients', 'Clientes')),
            const SizedBox(height: 8),
            _buildGrid(
              tp,
              wide,
              _actions
                  .where(
                    (a) =>
                        a.id == 'disconnect' ||
                        a.id == 'unpair_all' ||
                        a.id == 'update',
                  )
                  .toList(),
            ),
            const SizedBox(height: 18),
            _sectionLabel(_t(context, 'Media & Display', 'Medios y Pantalla')),
            const SizedBox(height: 8),
            _buildGrid(
              tp,
              wide,
              _actions
                  .where(
                    (a) =>
                        a.id == 'covers' ||
                        a.id == 'display' ||
                        a.id == 'force_sync',
                  )
                  .toList(),
            ),
            const SizedBox(height: 18),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: Colors.white.withValues(alpha: 0.30),
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1,
    ),
  );

  Widget _buildTokenRow(ThemeProvider tp) {
    return Focus(
      onKeyEvent: (_, ev) {
        if (ev is! KeyDownEvent) return KeyEventResult.ignored;
        if (ev.logicalKey == LogicalKeyboardKey.enter ||
            ev.logicalKey == LogicalKeyboardKey.select ||
            ev.logicalKey == LogicalKeyboardKey.gameButtonA) {
          setState(() => _tokenVisible = !_tokenVisible);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (_) => setState(() {}),
      child: Builder(
        builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: () => setState(() => _tokenVisible = !_tokenVisible),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: focused
                    ? tp.accent.withValues(alpha: 0.12)
                    : tp.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: focused
                      ? tp.accent.withValues(alpha: 0.40)
                      : Colors.white.withValues(alpha: 0.07),
                  width: focused ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.vpn_key_outlined,
                        color: focused ? tp.accent : Colors.white38,
                        size: 15,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _t(context, 'API Token', 'Token de API'),
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Token validity badge
                      if (_tokenOk == true)
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF30D158),
                          size: 14,
                        )
                      else if (_tokenOk == false)
                        const Icon(
                          Icons.cancel_rounded,
                          color: Color(0xFFFF453A),
                          size: 14,
                        ),
                      const Spacer(),
                      // Test button
                      GestureDetector(
                        onTap: _validating ? null : _validateToken,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: tp.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: tp.accent.withValues(alpha: 0.30),
                            ),
                          ),
                          child: _validating
                              ? SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: tp.accent,
                                  ),
                                )
                              : Text(
                                  _t(context, 'Test', 'Probar'),
                                  style: TextStyle(
                                    color: tp.accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _tokenVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.white30,
                        size: 15,
                      ),
                    ],
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 200),
                    crossFadeState: _tokenVisible
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox(
                      width: double.infinity,
                      height: 0,
                    ),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _tokenCtrl,
                              obscureText: true,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                              decoration: InputDecoration(
                                hintText: _t(
                                  context,
                                  'Paste Bearer token here…',
                                  'Pega el Bearer token aqui…',
                                ),
                                hintStyle: const TextStyle(
                                  color: Colors.white24,
                                  fontSize: 13,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: _saveToken,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () async {
                              final d = await Clipboard.getData(
                                Clipboard.kTextPlain,
                              );
                              if (d?.text != null &&
                                  d!.text!.isNotEmpty &&
                                  mounted) {
                                setState(() => _tokenCtrl.text = d.text!);
                                _saveToken(d.text!);
                              }
                            },
                            child: const Icon(
                              Icons.content_paste_rounded,
                              color: Colors.white30,
                              size: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGrid(ThemeProvider tp, bool wide, List<_ApiAction> items) {
    final cols = wide ? 3 : 2;
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += cols) {
      final chunk = items.sublist(i, (i + cols).clamp(0, items.length));
      rows.add(
        Row(
          children: [
            for (var j = 0; j < chunk.length; j++) ...[
              if (j > 0) const SizedBox(width: 10),
              Expanded(
                child: _ActionCard(
                  action: chunk[j],
                  isLoading: _loadingId == chunk[j].id,
                  anyLoading: _loadingId != null,
                  tp: tp,
                  onTap: () => _exec(chunk[j]),
                ),
              ),
            ],
            for (var j = chunk.length; j < cols; j++) ...[
              const SizedBox(width: 10),
              const Expanded(child: SizedBox()),
            ],
          ],
        ),
      );
      if (i + cols < items.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }
}


class _ActionCard extends StatefulWidget {
  final _ApiAction action;
  final bool isLoading;
  final bool anyLoading;
  final ThemeProvider tp;
  final VoidCallback onTap;

  const _ActionCard({
    required this.action,
    required this.isLoading,
    required this.anyLoading,
    required this.tp,
    required this.onTap,
  });

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isDisabled = !widget.action.enabled;
    final dimmed = isDisabled || (widget.anyLoading && !widget.isLoading);
    final description = isDisabled
        ? _t(context, 'Temporarily disabled', 'Deshabilitado temporalmente')
        : widget.action.desc;

    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, ev) {
        if (ev is! KeyDownEvent) return KeyEventResult.ignored;
        final k = ev.logicalKey;
        if (k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.select ||
            k == LogicalKeyboardKey.gameButtonA) {
          if (isDisabled || widget.isLoading) {
            return KeyEventResult.handled;
          }
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: dimmed || widget.isLoading ? null : widget.onTap,
        child: AnimatedOpacity(
          opacity: dimmed ? 0.45 : 1.0,
          duration: const Duration(milliseconds: 180),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: _focused
                  ? widget.tp.accent.withValues(alpha: 0.12)
                  : widget.tp.surface.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _focused
                    ? widget.tp.accent.withValues(alpha: 0.42)
                    : Colors.white.withValues(alpha: 0.06),
                width: _focused ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      widget.action.icon,
                      color: isDisabled
                          ? Colors.white24
                          : widget.action.isDanger
                          ? Colors.redAccent.withValues(
                              alpha: _focused ? 1.0 : 0.6,
                            )
                          : _focused
                          ? widget.tp.accent
                          : Colors.white38,
                      size: 18,
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: widget.isLoading
                          ? const CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white38,
                            )
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  widget.action.label,
                  style: TextStyle(
                    color: isDisabled
                        ? Colors.white38
                        : widget.action.isDanger && _focused
                        ? Colors.redAccent
                        : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white.withValues(
                      alpha: isDisabled ? 0.22 : 0.28,
                    ),
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
