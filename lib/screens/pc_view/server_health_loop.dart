import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/auth_provider.dart';
import '../../providers/computer_provider.dart';
import '../../providers/theme_provider.dart';

/// Periodic reachability + session upkeep for the server-list surfaces.
///
/// This lived twice — once in `pc_view_screen.dart` and once in
/// `focus_mode_screen.dart` — and the two copies drifted: a fix to the session
/// handling landed in one and not the other, so focus mode kept signing users
/// out of the cloud on the first token expiry and hiding LAN servers they were
/// standing next to. One implementation, two hosts.
class ServerHealthLoop {
  ServerHealthLoop({
    required this.context,
    this.onSessionLost,
    Duration interval = const Duration(seconds: 5),
  }) : _interval = interval;

  /// Tick interval when the user has asked for performance mode.
  ///
  /// The loop itself is cheap, but each tick can fan out into a poll of every
  /// known server. On a TV box that is worth halving.
  static const _performanceInterval = Duration(seconds: 10);

  /// Host element's context. Reads providers and is checked for `mounted`
  /// before every tick via [BuildContext.mounted].
  final BuildContext context;

  /// Called when the cloud session is gone for good — not merely expired.
  /// Hosts use this to surface a sign-in prompt.
  final void Function()? onSessionLost;

  final Duration _interval;

  Timer? _timer;
  int _tick = 0;

  /// Poll every 6th tick (~30s) when idle.
  static const _pollEvery = 6;

  /// Check the cloud session every 12th tick (~60s).
  static const _sessionEvery = 12;

  /// While streaming, do nothing at all except every 24th tick (~2min).
  static const _streamingThrottle = 24;

  void start() {
    _timer?.cancel();
    final slowDown =
        context.mounted && context.read<ThemeProvider>().performanceMode;
    _timer = Timer.periodic(
      slowDown ? _performanceInterval : _interval,
      (_) => _run(),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _run() {
    if (!context.mounted) return;
    final provider = context.read<ComputerProvider>();
    final auth = context.read<AuthProvider>();

    final streaming = provider.activeSessionComputer != null;
    _tick++;
    if (streaming && _tick % _streamingThrottle != 0) return;

    unawaited(_tickAsync(provider, auth, streaming: streaming));
  }

  Future<void> _tickAsync(
    ComputerProvider provider,
    AuthProvider auth, {
    required bool streaming,
  }) async {
    if (!streaming && _tick % _pollEvery == 0) {
      for (final computer in provider.computers) {
        unawaited(provider.pollComputer(computer));
      }
    }

    if (_tick % _sessionEvery != 0 || !auth.isSignedIn) return;

    try {
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;
      if (session != null && session.isExpired) {
        // Try to renew before giving up. Signing out on the first expiry —
        // which happens routinely, and always when offline — hides every cloud
        // server the user owns, including the one on the same LAN.
        await client.auth.refreshSession();
      } else if (session == null && context.mounted) {
        auth.signOutFromCloud();
        onSessionLost?.call();
      }
    } catch (_) {
      // Refresh failed (offline, most likely). Keep the session: paired servers
      // stay reachable over the LAN regardless of the cloud.
    }
  }
}
