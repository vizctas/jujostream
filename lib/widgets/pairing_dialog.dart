import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../models/computer_details.dart';
import '../providers/computer_provider.dart';
import '../providers/theme_provider.dart';
import '../services/crypto/client_identity.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _pair());
  }

  void _abort() {
    _bail = true;
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

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
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
        title: const Text('Pairing Required',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter this PIN in Sunshine/Apollo to authorize JUJO:',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F3460).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF0F3460)),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: widget.pin.split('').map((digit) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: 46,
                        height: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F3460),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          digit,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  Positioned(
                    right: 0,
                    child: IconButton(
                      icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 22),
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
                      tooltip: 'Copy PIN',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final addr = widget.computer.activeAddress.isNotEmpty
                      ? widget.computer.activeAddress
                      : widget.computer.localAddress;
                  final port = widget.computer.externalPort > 0 
                      ? widget.computer.externalPort + 1 
                      : 47990;
                  final url = Uri.parse('https://$addr:$port');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.open_in_browser_rounded, size: 20),
                label: const Text('Open Server Dashboard'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
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
            onPressed: _busy ? _abort : () => Navigator.pop(context, false),
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
