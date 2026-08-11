import 'package:flutter/material.dart';

Future<bool> showNotificationAccessDisclosure(BuildContext context) async {
  final spanish = Localizations.localeOf(context).languageCode == 'es';
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(spanish ? 'Acceso a notificaciones' : 'Notification access'),
      content: Text(
        spanish
            ? 'JUJO puede leer la app, titulo y contenido de notificaciones de otras apps. Solo se envian apps permitidas al dispositivo JUJO que emparejes. El contenido viaja cifrado, no se almacena remotamente y puedes revocar el acceso o eliminar dispositivos desde Ajustes.'
            : 'JUJO can read the app, title, and body of notifications from other apps. Only allowed apps are sent to the JUJO device you pair. Content is encrypted, is not stored remotely, and you can revoke access or remove devices in Settings.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(spanish ? 'Cancelar' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(spanish ? 'Continuar' : 'Continue'),
        ),
      ],
    ),
  );
  return result ?? false;
}
