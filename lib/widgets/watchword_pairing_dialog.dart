import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/computer_details.dart';
import '../providers/theme_provider.dart';
import '../providers/computer_provider.dart';
import '../services/pairing/watchword_service.dart';
import '../services/crypto/client_identity.dart';
import '../services/tv/tv_focus_helpers.dart';
import '../ui/motion_policy.dart';
import 'package:provider/provider.dart';

/// Consigna / Watchword pairing — pick the secret words out of a larger set.
///
/// Exists because entering a PIN with a D-pad means driving an on-screen
/// keyboard, which is slow everywhere and outright broken on some TV boxes.
/// Selecting from a grid is native remote navigation.
///
/// Returns true when the device paired.
Future<bool> showWatchwordPairingDialog(
  BuildContext context,
  ComputerDetails computer,
) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WatchwordPairingDialog(computer: computer),
  );
  return result ?? false;
}

class _WatchwordPairingDialog extends StatefulWidget {
  const _WatchwordPairingDialog({required this.computer});

  final ComputerDetails computer;

  @override
  State<_WatchwordPairingDialog> createState() =>
      _WatchwordPairingDialogState();
}

enum _Phase { loading, selecting, submitting, noChallenge, failed, paired }

class _WatchwordPairingDialogState extends State<_WatchwordPairingDialog> {
  final _service = WatchwordService();

  _Phase _phase = _Phase.loading;
  WatchwordChallenge? _challenge;
  final List<String> _picked = [];
  String? _message;
  Timer? _poll;
  int _lastRound = 1;

  @override
  void initState() {
    super.initState();
    _load(begin: true);
    // The words can rotate under us if nobody starts answering in time; keep
    // the grid honest rather than letting the user pick a dead set.
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _service.dispose();
    super.dispose();
  }

  String get _address => widget.computer.activeAddress.isNotEmpty
      ? widget.computer.activeAddress
      : widget.computer.localAddress;

  Future<void> _load({bool begin = false}) async {
    final challenge = await _service.fetchChallenge(
      address: _address,
      port: widget.computer.externalPort,
      uniqueId: ClientIdentity.uniqueId,
      begin: begin,
    );
    if (!mounted) return;
    setState(() {
      _challenge = challenge;
      _lastRound = challenge?.round ?? 1;
      _phase = challenge == null ? _Phase.noChallenge : _Phase.selecting;
    });
  }

  /// Re-reads the challenge without claiming it again. If the round advanced,
  /// the words on screen are stale and any partial selection is meaningless.
  Future<void> _refresh() async {
    if (_phase != _Phase.selecting) return;
    final challenge = await _service.fetchChallenge(
      address: _address,
      port: widget.computer.externalPort,
      uniqueId: ClientIdentity.uniqueId,
    );
    if (!mounted) return;

    if (challenge == null) {
      setState(() {
        _phase = _Phase.noChallenge;
        _challenge = null;
      });
      return;
    }
    if (challenge.round != _lastRound) {
      setState(() {
        _challenge = challenge;
        _lastRound = challenge.round;
        _picked.clear();
        _message = _isEs
            ? 'Las palabras cambiaron. Mira la pantalla otra vez.'
            : 'The words changed. Check the screen again.';
      });
      return;
    }
    setState(() => _challenge = challenge);
  }

  bool get _isEs => Localizations.localeOf(context).languageCode == 'es';

  void _toggle(String word) {
    final challenge = _challenge;
    if (challenge == null || _phase != _Phase.selecting) return;

    setState(() {
      _message = null;
      if (_picked.contains(word)) {
        // Removing anything but the last would silently reorder the rest.
        if (_picked.last == word) _picked.removeLast();
        return;
      }
      if (_picked.length >= challenge.wordCount) return;
      _picked.add(word);
    });

    if (_picked.length == challenge.wordCount) {
      _submit();
    }
  }

  Future<void> _submit() async {
    final challenge = _challenge;
    if (challenge == null) return;

    setState(() {
      _phase = _Phase.submitting;
      _message = _isEs ? 'Verificando…' : 'Verifying…';
    });

    // Through the provider, never PairingService directly: the provider is
    // what stores the server certificate, flips pairState, persists, and
    // notifies. Calling the service alone paired on the wire but left the
    // client showing "not paired".
    final result = await context.read<ComputerProvider>().pairComputer(
      widget.computer,
      challenge.challengeId,
      watchwordAnswer: List<String>.from(_picked),
    );
    if (!mounted) return;

    if (result.paired) {
      setState(() => _phase = _Phase.paired);
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    // The server owns the penalty; re-reading tells us whether it rotated the
    // words, is holding us in a wait, or gave up on the challenge entirely.
    setState(() {
      _picked.clear();
      _phase = _Phase.selecting;
      _message = _isEs
          ? 'Palabras u orden incorrectos. Intenta de nuevo.'
          : 'Wrong words or order. Try again.';
    });
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>().colors;
    final motion = MotionPolicy.fromContext(
      context,
      context.read<ThemeProvider>(),
    );

    return Dialog(
      backgroundColor: tp.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(tp),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                child: _body(tp, motion),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 16, 12),
              child: _footer(tp),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(dynamic tp) {
    final challenge = _challenge;
    final showTimer = challenge != null && _phase == _Phase.selecting;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 22, 20, 22),
      decoration: BoxDecoration(
        // A quiet accent wash so the header reads as a distinct, premium band
        // rather than a plain title row.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tp.accent.withValues(alpha: 0.20),
            tp.accent.withValues(alpha: 0.04),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: tp.accent.withValues(alpha: 0.25)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tp.accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.vpn_key_rounded, color: tp.accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEs ? 'Consigna' : 'Watchword',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  _isEs ? 'Emparejamiento por palabras' : 'Word pairing',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          if (showTimer)
            _CountdownRing(
              seconds: challenge.remainingSeconds,
              accent: tp.accent,
            ),
        ],
      ),
    );
  }

  Widget _body(dynamic tp, MotionPolicy motion) {
    switch (_phase) {
      case _Phase.loading:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );

      case _Phase.noChallenge:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            _isEs
                ? 'No hay una consigna activa. En Jujo.Stream Admin, presiona '
                      'Consigna para generar las palabras y vuelve aquí.'
                : 'No active watchword. In Jujo.Stream Admin, press Watchword '
                      'to generate the words, then come back.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
        );

      case _Phase.paired:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.greenAccent),
              const SizedBox(width: 10),
              Text(
                _isEs ? 'Emparejado' : 'Paired',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        );

      case _Phase.failed:
      case _Phase.selecting:
      case _Phase.submitting:
        return _grid(tp, motion);
    }
  }

  Widget _grid(dynamic tp, MotionPolicy motion) {
    final challenge = _challenge;
    if (challenge == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isEs
                ? 'Selecciona las ${challenge.wordCount} palabras en el mismo '
                      'orden que muestra Jujo.Stream Admin.'
                : 'Select the ${challenge.wordCount} words in the same order '
                      'Jujo.Stream Admin shows.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              // Three across on a phone, four when there is room. Derived from
              // the real width rather than a fixed count so this works on a
              // 1920 TV and a narrow phone alike.
              final columns = constraints.maxWidth > 520 ? 4 : 3;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: challenge.words.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.6,
                ),
                itemBuilder: (context, index) {
                  final word = challenge.words[index];
                  final order = _picked.indexOf(word);
                  return _WordTile(
                    word: word,
                    order: order >= 0 ? order + 1 : null,
                    autofocus: index == 0,
                    enabled: _phase == _Phase.selecting,
                    motion: motion,
                    onSelect: () => _toggle(word),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _footer(dynamic tp) {
    final challenge = _challenge;
    return Row(
      children: [
        Expanded(
          child: Text(
            _message ??
                (challenge == null
                    ? ''
                    : _isEs
                    ? 'Ronda ${challenge.round} de ${challenge.maxRounds}'
                    : 'Round ${challenge.round} of ${challenge.maxRounds}'),
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        TvFocusable(
          onSelect: () => Navigator.of(context).pop(false),
          borderRadius: 10,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              _isEs ? 'Cancelar' : 'Cancel',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact countdown ring for the header. A shrinking arc reads faster from a
/// couch than a number alone, and turns warm as time runs low.
class _CountdownRing extends StatelessWidget {
  const _CountdownRing({required this.seconds, required this.accent});

  final int seconds;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final low = seconds <= 10;
    final color = low ? const Color(0xFFFF6B6B) : accent;
    // 30s round is the reference; clamp so a frozen (extended) challenge does
    // not overfill the ring.
    final progress = (seconds / 30).clamp(0.0, 1.0);

    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 3,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text(
            '$seconds',
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// One word in the grid. Shows its position once picked, so the user can see
/// the order they have built rather than having to remember it.
class _WordTile extends StatelessWidget {
  const _WordTile({
    required this.word,
    required this.order,
    required this.autofocus,
    required this.enabled,
    required this.motion,
    required this.onSelect,
  });

  final String word;
  final int? order;
  final bool autofocus;
  final bool enabled;
  final MotionPolicy motion;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>().colors;
    final picked = order != null;

    return TvFocusable(
      autofocus: autofocus,
      enabled: enabled,
      onSelect: onSelect,
      borderRadius: 12,
      semanticLabel: word,
      child: AnimatedContainer(
        duration: motion.focusDuration,
        curve: motion.standardCurve,
        decoration: BoxDecoration(
          color: picked
              ? tp.accent.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: picked ? tp.accent : Colors.white24,
            width: picked ? 2 : 1,
          ),
          // A tinted lift on the chosen chips, never a flat black drop shadow.
          boxShadow: picked
              ? [
                  BoxShadow(
                    color: tp.accent.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (picked) ...[
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tp.accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$order',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                word,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
