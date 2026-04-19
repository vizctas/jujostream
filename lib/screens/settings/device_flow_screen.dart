import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/auth/google_auth_service.dart';

class DeviceFlowScreen extends StatefulWidget {
  const DeviceFlowScreen({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const DeviceFlowScreen()),
    );
    return result ?? false;
  }

  @override
  State<DeviceFlowScreen> createState() => _DeviceFlowScreenState();
}

class _DeviceFlowScreenState extends State<DeviceFlowScreen> {
  DeviceCodeResult? _deviceCode;
  String _status = 'requesting';
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _startFlow();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _startFlow() async {
    final auth = context.read<AuthProvider>();
    final result = await auth.startDeviceFlow();
    if (_disposed) return;
    if (result == null) {
      setState(() => _status = 'error');
      return;
    }
    setState(() {
      _deviceCode = result;
      _status = 'waiting';
    });

    final ok = await auth.pollDeviceFlow(
      result,
      onStatus: (s) {
        if (!_disposed) setState(() => _status = s);
      },
    );
    if (_disposed) return;
    if (ok) {
      setState(() => _status = 'authorized');
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context, true);
    } else {
      setState(() => _status = 'failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    return Scaffold(
      backgroundColor: tp.background,
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.goBack ||
              event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.gameButtonB) {
            Navigator.pop(context, false);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: _buildContent(tp),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeProvider tp) {
    if (_status == 'requesting') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: tp.accent),
          const SizedBox(height: 16),
          const Text('Requesting device code...',
              style: TextStyle(color: Colors.white70, fontSize: 18)),
        ],
      );
    }

    if (_status == 'error') {
      return _buildErrorWithClientIdSetup(tp);
    }

    if (_status == 'authorized') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: Colors.greenAccent.shade400, size: 80),
          const SizedBox(height: 16),
          const Text('Signed in!',
              style: TextStyle(
                  color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        ],
      );
    }

    if (_status == 'failed' ||
        _status == 'expired_token' ||
        _status == 'access_denied') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 64),
          const SizedBox(height: 16),
          Text(
            _status == 'access_denied' ? 'Access denied.' : 'Code expired.',
            style: const TextStyle(color: Colors.white, fontSize: 20),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() => _status = 'requesting');
              _startFlow();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: tp.accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Try Again'),
          ),
        ],
      );
    }

    final code = _deviceCode!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.tv, color: Colors.white54, size: 48),
        const SizedBox(height: 24),
        const Text(
          'Sign in with Google',
          style: TextStyle(
              color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Text(
          'On your phone or computer, go to:',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: tp.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            code.verificationUrl,
            style: TextStyle(
              color: tp.accent,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Then enter this code:',
            style: TextStyle(color: Colors.white70, fontSize: 16)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            color: tp.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tp.accent.withValues(alpha: 0.5), width: 2),
          ),
          child: Text(
            code.userCode,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: tp.accent,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Waiting for authorization...',
                style: TextStyle(color: Colors.white54, fontSize: 14)),
          ],
        ),
      ],
    );
  }

  final _clientIdController = TextEditingController();
  bool _savingClientId = false;

  Widget _buildErrorWithClientIdSetup(ThemeProvider tp) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.vpn_key_outlined, color: Colors.amberAccent, size: 56),
          const SizedBox(height: 16),
          const Text(
            'Google OAuth Client ID Required',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'To sign in on TV, you need a Google OAuth Client ID.\n\n'
            '1. Go to console.cloud.google.com\n'
            '2. Create an OAuth 2.0 Client ID (type: TVs and Limited Input)\n'
            '3. Paste the Client ID below',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: 24),

          TextField(
            controller: _clientIdController,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'xxxx.apps.googleusercontent.com',
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
              filled: true,
              fillColor: tp.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tp.accent, width: 2),
              ),
              prefixIcon: const Icon(Icons.key, color: Colors.white38, size: 20),
            ),
            onSubmitted: (_) => _saveClientIdAndRetry(tp),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _savingClientId ? null : () => _saveClientIdAndRetry(tp),
                  icon: _savingClientId
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check, size: 18),
                  label: Text(_savingClientId ? 'Saving...' : 'Save & Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tp.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: tp.surface,
                  foregroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Back'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'You can also configure this from the Companion Web UI on your phone.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _saveClientIdAndRetry(ThemeProvider tp) async {
    final clientId = _clientIdController.text.trim();
    if (clientId.isEmpty) return;
    setState(() => _savingClientId = true);
    await GoogleAuthService.instance.setClientId(clientId);
    if (!mounted) return;
    setState(() {
      _savingClientId = false;
      _status = 'requesting';
    });
    _startFlow();
  }
}
