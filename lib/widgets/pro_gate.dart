import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../services/pro/pro_service.dart';
import '../services/pro/billing_service.dart';

class ProGate extends StatelessWidget {
  final Widget child;
  final Widget? lockedChild;
  final ProFeature? feature;

  const ProGate({
    super.key,
    required this.child,
    this.lockedChild,
    this.feature,
  });

  factory ProGate.badge({
    Key? key,
    required Widget child,
    required String label,
    ProFeature? feature,
  }) {
    return ProGate(
      key: key,
      feature: feature,
      lockedChild: _LockedBadge(label: label),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

class ProBlurGate extends StatelessWidget {
  final Widget child;
  final ProFeature feature;
  final String? label;

  const ProBlurGate({
    super.key,
    required this.child,
    required this.feature,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

class _LockedBadge extends StatelessWidget {
  final String label;
  const _LockedBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_outline, size: 14, color: Colors.white54),
        const SizedBox(width: 6),
        Text(
          '$label · Pro',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class ProBadge extends StatelessWidget {
  const ProBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final tc = context.read<ThemeProvider>().colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: tc.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: tc.accentLight.withValues(alpha: 0.3)),
      ),
      child: Text('Pro', style: TextStyle(color: tc.accentLight, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
}

class ProUpsellDialog extends StatefulWidget {
  const ProUpsellDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const ProUpsellDialog(),
    );
  }

  @override
  State<ProUpsellDialog> createState() => _ProUpsellDialogState();
}

class _ProUpsellDialogState extends State<ProUpsellDialog> {
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scroll(double delta) {
    final pos = _scrollController.position;
    _scrollController.animateTo(
      (pos.pixels + delta).clamp(0.0, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  void _launchPurchase() {
    final billing = BillingService();
    if (!billing.buyPro()) {

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Store not available. Try again later.')),
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {

    final isEs = Localizations.localeOf(context).languageCode == 'es';
    final billing = BillingService();
    final title = isEs ? 'Mejora a Pro' : 'Upgrade to Pro';
    final subtitle = isEs
        ? 'Desbloquea la experiencia completa de JUJO Stream'
        : 'Unlock the full JUJO Stream experience';
    final benefits = [
      isEs ? 'Todos los esquemas de color y temas del launcher' : 'All color schemes & launcher themes',
      isEs ? 'Favoritos y colecciones ilimitados' : 'Unlimited favorites & collections',
      isEs ? 'Bitrate Inteligente, Cloud Sync y overlay avanzado' : 'Smart Bitrate, Cloud Sync & advanced overlay',
      isEs ? 'Plugins premium: Video Intro, Biblioteca Steam, Filtros de Género, Videos de Juegos' : 'Premium plugins: Intro Video, Steam Library, Genre Filters, Game Videos',
      isEs ? 'Arte en alta calidad, historial completo de sesiones y más' : 'High quality art, full session history & more',
      isEs ? 'Futuros temas y funcionalidades incluidos' : 'Future themes & features included',
    ];
    final price = billing.product?.price;
    final ctaLabel = price != null
        ? (isEs ? 'Obtener Pro — $price' : 'Get Pro — $price')
        : (isEs ? 'Obtener Pro' : 'Get Pro');
    final laterLabel = isEs ? 'Quizás después' : 'Maybe later';

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
        final k = event.logicalKey;

        if (k == LogicalKeyboardKey.gameButtonB ||
            k == LogicalKeyboardKey.escape ||
            k == LogicalKeyboardKey.goBack) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }

        if (k == LogicalKeyboardKey.arrowDown) {
          _scroll(80);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowUp) {
          _scroll(-80);
          return KeyEventResult.handled;
        }

        if (k == LogicalKeyboardKey.gameButtonA ||
            k == LogicalKeyboardKey.enter) {
          _launchPurchase();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Container(
        decoration: BoxDecoration(
          color: context.read<ThemeProvider>().colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: context.read<ThemeProvider>().colors.accent.withValues(alpha: 0.30),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.40),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ).createShader(bounds),
                blendMode: BlendMode.srcIn,
                child: const Icon(Icons.workspace_premium, size: 48, color: Colors.white),
              ),
              const SizedBox(height: 12),

              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),

              ...benefits.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check_circle, size: 16, color: Color(0xFF4CAF50)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        b,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _launchPurchase,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.read<ThemeProvider>().colors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const ProCrownBadge(size: 18),
                      const SizedBox(width: 8),
                      Text(
                        ctaLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  laterLabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '▲▼ Scroll  Ⓐ Pro  Ⓑ Close',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
              ),
            ],
          ),
          ),
        ),
        ),
        ),
      ),
    ),
    );
  }
}

class ProCrownBadge extends StatelessWidget {
  final double size;
  const ProCrownBadge({super.key, this.size = 16});

  static Widget withLabel(String label, {TextStyle? style}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ProCrownBadge(size: 15),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: style ?? const TextStyle(color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
