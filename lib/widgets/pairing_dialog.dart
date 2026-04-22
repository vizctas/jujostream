import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../models/computer_details.dart';
import '../providers/computer_provider.dart';
import '../providers/theme_provider.dart';
import '../services/crypto/client_identity.dart';

// ─── Flip-Clock Digit ─────────────────────────────────────────────────────────
//
// Split-flap mechanical display.
//
// Each digit box is a fixed-size container with 3D perspective.
// The flip animates from blank → digit using two phases:
//   Phase 1: Upper flap (blank) falls forward  0° → –90°
//   Phase 2: Lower flap (digit) falls into place  90° → 0°
//
// The "cut in half" trick:
//   A full-height text widget is placed inside a half-height container.
//   For the TOP half: text is aligned to top, bottom overflows and is clipped.
//   For the BOTTOM half: text is shifted UP by half the total height via
//   a negative top offset, so only the bottom portion is visible.

class _FlipDigit extends StatefulWidget {
  final String digit;
  final Duration delay;
  final double width;
  final double height;
  final Color boxColor;
  final Color borderColor;
  final Color textColor;
  final bool skipAnimation;

  const _FlipDigit({
    required this.digit,
    required this.delay,
    required this.width,
    required this.height,
    required this.boxColor,
    required this.borderColor,
    required this.textColor,
    this.skipAnimation = false,
  });

  @override
  State<_FlipDigit> createState() => _FlipDigitState();
}

class _FlipDigitState extends State<_FlipDigit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    if (widget.skipAnimation) {
      _started = true;
      _ctrl.value = 1.0;
    } else {
      Future.delayed(widget.delay, () {
        if (!mounted) return;
        setState(() => _started = true);
        _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  TextStyle get _style => TextStyle(
        color: widget.textColor,
        fontSize: widget.height * 0.58,
        fontWeight: FontWeight.w700,
        height: 1.0,
      );

  double get _halfH => widget.height / 2;

  /// Renders the TOP half of [text] — clips away the bottom.
  Widget _topHalf(String text) {
    return SizedBox(
      width: widget.width,
      height: _halfH,
      child: ClipRect(
        child: OverflowBox(
          maxHeight: widget.height,
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: widget.height,
            width: widget.width,
            child: Center(child: Text(text, style: _style)),
          ),
        ),
      ),
    );
  }

  /// Renders the BOTTOM half of [text] — clips away the top.
  Widget _bottomHalf(String text) {
    return SizedBox(
      width: widget.width,
      height: _halfH,
      child: ClipRect(
        child: OverflowBox(
          maxHeight: widget.height,
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: widget.height,
            width: widget.width,
            child: Center(child: Text(text, style: _style)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.skipAnimation) {
      return _outerBox(
        child: Center(child: Text(widget.digit, style: _style)),
      );
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        final inPhase1 = t < 0.5;
        final phase1 = (t / 0.5).clamp(0.0, 1.0);
        final phase2 = ((t - 0.5) / 0.5).clamp(0.0, 1.0);

        // Upper flap: 0 → –π/2 (easeIn)
        final upperAngle = Curves.easeIn.transform(phase1) * (-math.pi / 2);
        // Lower flap: π/2 → 0 (easeOut)
        final lowerAngle =
            (1.0 - Curves.easeOut.transform(phase2)) * (math.pi / 2);

        return _outerBox(
          child: Stack(
            children: [
              // ── STATIC BACKGROUND: top half shows NEW digit ──
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _started ? _topHalf(widget.digit) : _topHalf(''),
              ),

              // ── STATIC BACKGROUND: bottom half shows NEW digit after done ──
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: (t >= 1.0 && _started)
                    ? _bottomHalf(widget.digit)
                    : _bottomHalf(''),
              ),

              // ── UPPER FLAP: blank panel, falls forward ──
              if (_started && inPhase1)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateX(upperAngle),
                    child: Stack(
                      children: [
                        Container(
                          width: widget.width,
                          height: _halfH,
                          decoration: BoxDecoration(
                            color: widget.boxColor,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                          ),
                        ),
                        // Darken overlay as flap falls
                        Container(
                          width: widget.width,
                          height: _halfH,
                          decoration: BoxDecoration(
                            color:
                                Colors.black.withValues(alpha: phase1 * 0.5),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── LOWER FLAP: shows NEW digit, falls into place ──
              if (_started && !inPhase1 && t < 1.0)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Transform(
                    alignment: Alignment.topCenter,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateX(lowerAngle),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(6),
                          ),
                          child: Container(
                            color: widget.boxColor,
                            child: _bottomHalf(widget.digit),
                          ),
                        ),
                        // Darken overlay, brightens as flap lands
                        Container(
                          width: widget.width,
                          height: _halfH,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(
                                alpha: (1.0 - phase2) * 0.5),
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Center divider line ──
              Positioned(
                top: _halfH - 0.5,
                left: 0,
                right: 0,
                child: Container(
                  height: 1,
                  color: Colors.black.withValues(alpha: 0.2),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _outerBox({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: widget.boxColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: child,
      ),
    );
  }
}

// ─── Pairing Dialog ───────────────────────────────────────────────────────────

class PairingDialog extends StatefulWidget {
  final ComputerDetails computer;
  final String pin;

  const PairingDialog({super.key, required this.computer, required this.pin});

  @override
  State<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<PairingDialog>
    with WidgetsBindingObserver {
  bool _busy = true;
  String? _err;
  bool _bail = false;

  /// Tracks whether the app went to background while Phase 1 was in-flight.
  /// Used on [resumed] to auto-retry if pairing failed while backgrounded.
  bool _wentToBackgroundDuringPairing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Delay pairing by the total duration of the flip animation plus a small buffer
    // Initial delay + (3 staggers * 250) + flip animation (500)
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) _pair();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Lifecycle guard for same-device pairing.
  ///
  /// CRITICAL: We do NOT cancel pairing on [paused].
  ///
  /// Reason: In Sunshine/Apollo, Phase 1 (getservercert) is the BLOCKING
  /// long-poll that the server holds open until the user enters the PIN.
  /// Cancelling it would kill Phase 1 mid-wait, produce "out of order
  /// getservercert" on retry, and force the user to re-enter the PIN.
  ///
  /// Correct behavior: let Phase 1 complete naturally in the background.
  /// When the user enters the PIN in Chrome, the server responds → Phase 1
  /// returns → Phases 2-5 complete in seconds → pairing succeeds, possibly
  /// while the user is still in Chrome (dialog will dismiss on return).
  ///
  /// If pairing failed while backgrounded (network killed Phase 1's TCP),
  /// auto-retry fires on [resumed] so the user just re-enters the same PIN.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _busy && !_bail) {
      _wentToBackgroundDuringPairing = true;
      // Do NOT call cancelActivePairing() here — see doc above.
    } else if (state == AppLifecycleState.resumed &&
        _wentToBackgroundDuringPairing) {
      _wentToBackgroundDuringPairing = false;
      if (_bail) return;

      // If pairing failed while we were in the background (e.g. TCP killed),
      // auto-retry now that we're in foreground with stable network.
      if (!_busy && _err != null) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && !_bail) _pair();
        });
      }
      // If _busy == true: Phase 1 is still waiting for server response.
      // Nothing to do — let it complete; the dialog will update naturally.
    }
  }

  void _abort() {
    _bail = true;
    // Signal explicit user-initiated cancellation.
    context.read<ComputerProvider>().cancelActivePairing();
    final addr = widget.computer.activeAddress.isNotEmpty
        ? widget.computer.activeAddress
        : widget.computer.localAddress;
    final p =
        widget.computer.externalPort > 0 ? widget.computer.externalPort : 47989;
    try {
      http.Client()
          .get(Uri.parse(
              'http://$addr:$p/unpair?uniqueid=${ClientIdentity.uniqueId}'))
          .timeout(const Duration(seconds: 3))
          .whenComplete(() {});
    } catch (_) {}
    Navigator.pop(context, false);
  }

  Future<void> _pair() async {
    if (!mounted || _bail) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    final res = await context
        .read<ComputerProvider>()
        .pairComputer(widget.computer, widget.pin);
    if (!mounted || _bail) return;
    if (res.paired) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _err = res.error ?? 'Pairing failed';
    });
  }

  /// Derives the Sunshine/Apollo web UI port.
  ///
  /// Sunshine port scheme (from the configured "port" value):
  ///   HTTPS  = port - 5
  ///   HTTP   = port        ← this is what externalPort stores
  ///   Web UI = port + 1
  ///
  /// So: webUiPort = externalPort + 1
  int get _webUiPort {
    final ext = widget.computer.externalPort;
    return ext > 0 ? ext + 1 : 47990;
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
    final isLight = tp.colors.isLight;
    final skipAnim = tp.reduceEffects;

    const initialDelay = Duration(milliseconds: 1000);
    const stagger = Duration(milliseconds: 250);

    return Focus(
      skipTraversal: true,
      onKeyEvent: (_, ev) {
        if (ev is! KeyDownEvent) return KeyEventResult.ignored;
        final k = ev.logicalKey;
        if (k == LogicalKeyboardKey.gameButtonB ||
            k == LogicalKeyboardKey.escape ||
            k == LogicalKeyboardKey.goBack) {
          _abort();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AlertDialog(
        backgroundColor: tp.surface,
        title: Text(
          'Pairing Required',
          style: TextStyle(
            color: isLight ? Colors.black87 : Colors.white,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter this PIN in Sunshine/Apollo to authorize JUJO:',
              style: TextStyle(
                color: isLight ? Colors.black54 : Colors.white70,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.pin.length, (i) {
                return _FlipDigit(
                  digit: widget.pin[i],
                  delay: initialDelay + stagger * i,
                  width: 46,
                  height: 56,
                  boxColor: tp.surfaceVariant,
                  borderColor: tp.accent.withValues(alpha: 0.4),
                  textColor: isLight ? Colors.black87 : Colors.white,
                  skipAnimation: skipAnim,
                );
              }),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.pin));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('PIN copied to clipboard'),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 20),
                label: const Text('Copy PIN'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isLight ? Colors.black87 : Colors.white,
                  side: BorderSide(
                    color: isLight ? Colors.black26 : Colors.white24,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final addr = widget.computer.activeAddress.isNotEmpty
                      ? widget.computer.activeAddress
                      : widget.computer.localAddress;
                  final url = Uri.parse('https://$addr:$_webUiPort');
                  launchUrl(url, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.open_in_browser_rounded, size: 20),
                label: const Text('Open Server Dashboard'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isLight ? Colors.black87 : Colors.white,
                  side: BorderSide(
                    color: isLight ? Colors.black26 : Colors.white24,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_busy)
              const Row(children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Expanded(
                    child: Text('Pairing in progress...',
                        style: TextStyle(color: Colors.white70))),
              ]),
            if (_err != null) ...[
              const SizedBox(height: 8),
              Text(_err!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed:
                _busy ? _abort : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          if (!_busy)
            ElevatedButton(
              onPressed: _pair,
              style: ElevatedButton.styleFrom(
                backgroundColor: tp.accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

/// Shows the pairing dialog and returns `true` if pairing succeeded.
Future<bool> showPairingDialog(
    BuildContext context, ComputerDetails computer) async {
  final pin = context.read<ComputerProvider>().generatePairingPin();
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PairingDialog(computer: computer, pin: pin),
  );
  return ok ?? false;
}
