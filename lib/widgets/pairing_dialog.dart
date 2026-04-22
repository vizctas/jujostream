import 'dart:io' as io;
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

// ─── Notification Permission Helper ───────────────────────────────────────────
//
// Uses the existing pairing_locks MethodChannel to check/request the
// POST_NOTIFICATIONS permission on Android 13+.

const MethodChannel _pairingLocksChannel =
    MethodChannel('com.jujostream/pairing_locks');

/// Returns "granted", "denied", or "not_required".
Future<String> _checkNotificationPermission() async {
  if (!io.Platform.isAndroid) return 'not_required';
  try {
    final result =
        await _pairingLocksChannel.invokeMethod<String>('checkNotificationPermission');
    return result ?? 'not_required';
  } on PlatformException {
    return 'not_required';
  }
}

/// Requests the permission via the system dialog.
/// Returns "granted", "denied", or "not_required".
Future<String> _requestNotificationPermission() async {
  if (!io.Platform.isAndroid) return 'not_required';
  try {
    final result =
        await _pairingLocksChannel.invokeMethod<String>('requestNotificationPermission');
    return result ?? 'not_required';
  } on PlatformException {
    return 'not_required';
  }
}

/// Opens the OS notification settings page for this app.
Future<void> _openNotificationSettings() async {
  if (!io.Platform.isAndroid) return;
  try {
    await _pairingLocksChannel.invokeMethod<bool>('openNotificationSettings');
  } on PlatformException {
    // ignore
  }
}

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

class _PairingDialogState extends State<PairingDialog> {
  bool _busy = true;
  String? _err;
  bool _bail = false;

  @override
  void initState() {
    super.initState();
    // Delay pairing by the total duration of the flip animation plus a small buffer
    // Initial delay + (3 staggers * 250) + flip animation (500)
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) _pair();
    });
  }

  void _abort() {
    _bail = true;
    // Signal explicit user-initiated cancellation.
    // This sets _cancelRequested in PairingService, which causes the
    // native poll loop to call 'release' → stops the FGS + cancel flag.
    context.read<ComputerProvider>().cancelActivePairing();

    // Best-effort server-side cleanup: tell the server to drop the
    // pairing session so it doesn't linger. Fire-and-forget with
    // proper client cleanup to avoid socket leaks.
    final addr = widget.computer.activeAddress.isNotEmpty
        ? widget.computer.activeAddress
        : widget.computer.localAddress;
    final p =
        widget.computer.externalPort > 0 ? widget.computer.externalPort : 47989;
    final client = http.Client();
    client
        .get(Uri.parse(
            'http://$addr:$p/unpair?uniqueid=${ClientIdentity.uniqueId}'))
        .timeout(const Duration(seconds: 3))
        .whenComplete(client.close)
        .ignore();
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
///
/// On Android 13+ this first checks the POST_NOTIFICATIONS permission.
/// If denied, a disclaimer dialog explains why it is critical and offers
/// to re-request or open system settings. Pairing only proceeds once the
/// user either grants the permission or explicitly chooses to continue
/// without it.
Future<bool> showPairingDialog(
    BuildContext context, ComputerDetails computer) async {
  // ── Notification permission gate (Android 13+) ──────────────────────
  if (io.Platform.isAndroid) {
    final status = await _checkNotificationPermission();
    if (status == 'denied' && context.mounted) {
      final proceed = await _showNotificationDisclaimer(context);
      if (!proceed || !context.mounted) return false;
    }
  }

  if (!context.mounted) return false;
  final pin = context.read<ComputerProvider>().generatePairingPin();
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PairingDialog(computer: computer, pin: pin),
  );
  return ok ?? false;
}

/// Disclaimer dialog explaining why notification permission is required.
///
/// Returns `true` if the user granted permission or chose to continue
/// without it, `false` if the user cancelled.
Future<bool> _showNotificationDisclaimer(BuildContext context) async {
  final tp = context.read<ThemeProvider>();
  final isLight = tp.colors.isLight;

  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: tp.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: Icon(
        Icons.notifications_active_rounded,
        color: Colors.orangeAccent,
        size: 40,
      ),
      title: Text(
        'Notification Permission Required',
        style: TextStyle(
          color: isLight ? Colors.black87 : Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 17,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'JUJO needs notification permission to pair with your server.',
            style: TextStyle(
              color: isLight ? Colors.black87 : Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          _disclaimerBullet(
            Icons.phone_android_rounded,
            'When you open the browser to enter the PIN, JUJO goes to the background.',
            isLight,
          ),
          const SizedBox(height: 8),
          _disclaimerBullet(
            Icons.vpn_key_rounded,
            'The PIN is shown in the notification so you can see it without switching apps.',
            isLight,
          ),
          const SizedBox(height: 8),
          _disclaimerBullet(
            Icons.wifi_protected_setup_rounded,
            'The pairing handshake runs as a background service that survives the app being minimized.',
            isLight,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.orangeAccent.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.orangeAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Without this permission, pairing may fail on single-device setups.',
                    style: TextStyle(
                      color: Colors.orangeAccent.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'cancel'),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: isLight ? Colors.black54 : Colors.white54,
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'skip'),
              child: Text(
                'Continue Anyway',
                style: TextStyle(
                  color: isLight ? Colors.black54 : Colors.white54,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'grant'),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Allow'),
              style: ElevatedButton.styleFrom(
                backgroundColor: tp.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  if (result == 'cancel' || result == null) return false;
  if (result == 'skip') return true;

  // result == 'grant' → request the permission
  final permResult = await _requestNotificationPermission();
  if (permResult == 'granted') return true;

  // Still denied after the system dialog — the user tapped "Don't allow"
  // or the system won't show the dialog again (permanently denied).
  // Offer to open settings.
  if (!context.mounted) return false;
  final settingsResult = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: tp.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(Icons.block_rounded, color: Colors.redAccent, size: 36),
      title: Text(
        'Permission Denied',
        style: TextStyle(
          color: isLight ? Colors.black87 : Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 17,
        ),
      ),
      content: Text(
        'Notifications are still blocked. You can enable them manually '
        'in Settings, or continue without the PIN notification.\n\n'
        'Without notifications, you will need to memorize the PIN before '
        'opening the browser.',
        style: TextStyle(
          color: isLight ? Colors.black54 : Colors.white70,
          fontSize: 13,
        ),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'cancel'),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'skip'),
          child: const Text('Continue Anyway'),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            await _openNotificationSettings();
            if (ctx.mounted) Navigator.pop(ctx, 'settings');
          },
          icon: const Icon(Icons.settings, size: 18),
          label: const Text('Open Settings'),
          style: ElevatedButton.styleFrom(
            backgroundColor: tp.accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    ),
  );

  if (settingsResult == 'cancel' || settingsResult == null) return false;
  if (settingsResult == 'skip') return true;

  // User went to settings — re-check when they come back
  if (context.mounted) {
    // Small delay to let the user toggle the setting and return
    await Future.delayed(const Duration(milliseconds: 500));
    final recheck = await _checkNotificationPermission();
    return recheck != 'denied';
  }
  return false;
}

Widget _disclaimerBullet(IconData icon, String text, bool isLight) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: isLight ? Colors.black38 : Colors.white38),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            color: isLight ? Colors.black54 : Colors.white60,
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
      ),
    ],
  );
}
