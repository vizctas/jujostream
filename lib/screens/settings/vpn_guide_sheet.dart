import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class VpnGuideSheet extends StatelessWidget {
  const VpnGuideSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.gameButtonB ||
              key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            Navigator.pop(ctx);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: const VpnGuideSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (context, scroll) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [

              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.vpn_lock_rounded,
                        color: cs.primary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Acceso Remoto (VPN)',
                              style: tt.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          Text(
                            'Conéctate a tu PC desde cualquier red',
                            style: tt.bodySmall
                                ?.copyWith(color: cs.onSurface.withValues(alpha: 0.6)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomPadding),
                  children: [
                    _InfoBanner(
                      icon: Icons.info_outline_rounded,
                      text:
                          'Para usar JujoStream fuera de casa necesitas que tu PC y tu dispositivo estén en la misma red virtual (VPN).',
                      color: cs.primaryContainer,
                      textColor: cs.onPrimaryContainer,
                    ),
                    const SizedBox(height: 16),
                    _VpnOption(
                      name: 'Tailscale',
                      tagline: 'Recomendado · Más fácil de configurar',
                      description:
                          'Crea una red personal segura en segundos. Solo instala en tu PC y en tu móvil — se conectan automáticamente.',
                      icon: Icons.shield_rounded,
                      badgeColor: Colors.green,
                      packageId: 'com.tailscale.ipn.android',
                      steps: const [
                        'Instala Tailscale en tu PC (tailscale.com)',
                        'Instala la app en este dispositivo',
                        'Inicia sesión con la misma cuenta en ambos',
                        'Vuelve a JujoStream y conecta normalmente',
                      ],
                    ),
                    const SizedBox(height: 12),
                    _VpnOption(
                      name: 'ZeroTier',
                      tagline: 'Alternativa gratuita · Más control',
                      description:
                          'Red virtual peer-to-peer. Crea una red en zerotier.com y únete desde ambos dispositivos.',
                      icon: Icons.hub_rounded,
                      badgeColor: Colors.blue,
                      packageId: 'com.zerotier.one',
                      steps: const [
                        'Crea una red en my.zerotier.com',
                        'Instala el cliente en tu PC',
                        'Instala la app en este dispositivo',
                        'Une ambos dispositivos a tu red',
                        'Aprueba los dispositivos en la consola web',
                      ],
                    ),
                    const SizedBox(height: 12),
                    _VpnOption(
                      name: 'WireGuard',
                      tagline: 'Para usuarios avanzados',
                      description:
                          'Protocolo VPN de alto rendimiento. Requiere configurar un servidor, pero ofrece la mejor velocidad y seguridad.',
                      icon: Icons.lock_rounded,
                      badgeColor: Colors.orange,
                      packageId: 'com.wireguard.android',
                      steps: const [
                        'Configura un servidor WireGuard en tu red (pfSense, router, etc.)',
                        'Exporta la configuración del cliente',
                        'Instala la app WireGuard en este dispositivo',
                        'Importa la configuración del cliente',
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle_outline_rounded,
                              color: cs.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Después de activar tu VPN, vuelve aquí y conecta a tu PC normalmente. JujoStream detectará tu PC automáticamente.',
                              style: tt.bodySmall?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VpnOption extends StatefulWidget {
  final String name;
  final String tagline;
  final String description;
  final IconData icon;
  final Color badgeColor;
  final String packageId;
  final List<String> steps;

  const _VpnOption({
    required this.name,
    required this.tagline,
    required this.description,
    required this.icon,
    required this.badgeColor,
    required this.packageId,
    required this.steps,
  });

  @override
  State<_VpnOption> createState() => _VpnOptionState();
}

class _VpnOptionState extends State<_VpnOption> {
  bool _expanded = false;
  bool _loading = false;

  Future<void> _openStore() async {
    setState(() => _loading = true);
    final marketUri =
        Uri.parse('market://details?id=${widget.packageId}');
    final fallbackUri = Uri.parse(
        'https://play.google.com/store/apps/details?id=${widget.packageId}');
    try {
      if (!await launchUrl(marketUri,
          mode: LaunchMode.externalApplication)) {
        await launchUrl(fallbackUri,
            mode: LaunchMode.externalApplication);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _expanded
              ? widget.badgeColor.withValues(alpha: 0.6)
              : cs.outline.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.icon,
                        color: widget.badgeColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.name,
                            style: tt.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text(widget.tagline,
                            style: tt.labelSmall?.copyWith(
                                color: widget.badgeColor,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, indent: 14, endIndent: 14),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.description,
                      style: tt.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.75))),
                  const SizedBox(height: 10),
                  ...widget.steps.asMap().entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: widget.badgeColor
                                    .withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${e.key + 1}',
                                style: TextStyle(
                                  color: widget.badgeColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(e.value,
                                  style: tt.bodySmall?.copyWith(
                                      color: cs.onSurface
                                          .withValues(alpha: 0.8))),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _openStore,
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_rounded, size: 18),
                      label: Text(_loading
                          ? 'Abriendo tienda…'
                          : 'Instalar ${widget.name}'),
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.badgeColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final Color textColor;

  const _InfoBanner({
    required this.icon,
    required this.text,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: textColor)),
          ),
        ],
      ),
    );
  }
}
