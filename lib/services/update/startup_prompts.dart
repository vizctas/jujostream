import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_version.dart';
import '../../utils/changelog.dart';
import 'update_models.dart';
import 'update_provider.dart';

/// Launch-time prompts: the "what's new" card once per installed version, then
/// an offer to download a newer release. Both are best-effort and silent on
/// any failure (offline, rate-limited GitHub, Play build without direct
/// install).
class StartupPrompts {
  static const seenVersionKey = 'changelog_seen_version';

  static Future<void> run(BuildContext context) async {
    await _showChangelogOnce(context);
    if (!context.mounted) return;
    await _offerUpdate(context);
  }

  static bool _es(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'es';

  static Future<void> _showChangelogOnce(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(seenVersionKey) == kAppVersion) return;
    await prefs.setString(seenVersionKey, kAppVersion);
    final entry = kChangelog[kAppVersion];
    if (entry == null || !context.mounted) return;
    final es = _es(context);
    await _showCard(
      context,
      title: es
          ? 'Novedades de la v$kAppVersion'
          : 'What\'s new in v$kAppVersion',
      body: (es ? entry.es : entry.en).map((line) => '•  $line').join('\n\n'),
      primary: es ? 'Entendido' : 'Got it',
    );
  }

  static Future<void> _offerUpdate(BuildContext context) async {
    final UpdateProvider updates;
    try {
      updates = context.read<UpdateProvider>();
    } on ProviderNotFoundException {
      return;
    }
    if (!updates.supportsDirectInstall) return;

    final ClientUpdateRelease? release;
    try {
      release = await updates.checkForUpdate();
    } catch (error) {
      debugPrint('[JUJO][update] check failed: $error');
      return;
    }
    if (release == null || !context.mounted) return;

    final es = _es(context);
    final accepted = await _showCard(
      context,
      title: es
          ? 'Nueva versión disponible: v${release.version}'
          : 'New version available: v${release.version}',
      body: [
        es
            ? 'Tienes la v$kAppVersion. ¿Quieres descargar e instalar la '
                  'v${release.version}?'
            : 'You have v$kAppVersion. Download and install '
                  'v${release.version}?',
        if (release.notes.isNotEmpty) release.notes,
      ].join('\n\n'),
      primary: es ? 'Descargar e instalar' : 'Download and install',
      secondary: es ? 'Más tarde' : 'Later',
    );
    if (accepted != true || !context.mounted) return;

    final progress = ValueNotifier<double?>(null);
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(es ? 'Descargando actualización' : 'Downloading update'),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (_, value, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: value),
                const SizedBox(height: 12),
                Text(value == null ? '…' : '${(value * 100).round()}%'),
              ],
            ),
          ),
        ),
      ),
    );

    File? apk;
    Object? failure;
    try {
      apk = await updates.downloadAndVerify(
        release,
        onProgress: (received, total) {
          if (total > 0) progress.value = (received / total).clamp(0, 1);
        },
      );
    } catch (error) {
      failure = error;
    }
    navigator.pop();
    progress.dispose();
    if (!context.mounted) return;
    if (apk == null) {
      debugPrint('[JUJO][update] download failed: $failure');
      await _showCard(
        context,
        title: es ? 'No se pudo descargar' : 'Download failed',
        body: es
            ? 'Vuelve a intentarlo más tarde o desde Acerca de.\n\n$failure'
            : 'Try again later or from About.\n\n$failure',
        primary: 'OK',
      );
      return;
    }
    await _install(context, updates, apk, es);
  }

  /// Android needs "install unknown apps" for this package. The system screen
  /// returns asynchronously, so after sending the user there we offer an
  /// explicit retry instead of guessing when they are back.
  static Future<void> _install(
    BuildContext context,
    UpdateProvider updates,
    File apk,
    bool es,
  ) async {
    while (context.mounted) {
      if (await updates.canInstallPackages()) {
        await updates.installApk(apk);
        return;
      }
      await updates.openInstallPermission();
      if (!context.mounted) return;
      final retry = await _showCard(
        context,
        title: es ? 'Permiso necesario' : 'Permission required',
        body: es
            ? 'Permite que JUJO Stream instale aplicaciones y luego pulsa '
                  'Instalar.'
            : 'Allow JUJO Stream to install apps, then press Install.',
        primary: es ? 'Instalar' : 'Install',
        secondary: es ? 'Cancelar' : 'Cancel',
      );
      if (retry != true) return;
    }
  }

  static Future<bool?> _showCard(
    BuildContext context, {
    required String title,
    required String body,
    required String primary,
    String? secondary,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(child: Text(body)),
        ),
        actions: [
          if (secondary != null)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(secondary),
            ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(primary),
          ),
        ],
      ),
    );
  }
}
