import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../platform_channels/invite_link_channel.dart';
import '../providers/auth_provider.dart';
import '../services/sync/guest_link.dart';

/// Redeems incoming invite links and reports every guest-join outcome as a
/// snackbar, wherever the user is in the app.
class GuestJoinListener extends StatefulWidget {
  const GuestJoinListener({super.key, required this.child});

  final Widget child;

  @override
  State<GuestJoinListener> createState() => _GuestJoinListenerState();
}

class _GuestJoinListenerState extends State<GuestJoinListener> {
  StreamSubscription<GuestJoinEvent>? _events;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _events = auth.guestJoinEvents.listen(_show);
    InviteLinkChannel.listen((link) {
      final code = guestCodeFromLink(link);
      if (code != null) auth.redeemGuestCode(code);
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  void _show(GuestJoinEvent event) {
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    final msg = switch (event.kind) {
      GuestJoinEventKind.needSignIn => l.guestNeedSignIn,
      GuestJoinEventKind.joined => l.guestJoined(event.serverName),
      GuestJoinEventKind.accepted => l.guestAccepted(event.serverName),
      GuestJoinEventKind.declined => l.guestDeclined,
      GuestJoinEventKind.expired => l.guestRequestExpired,
      GuestJoinEventKind.verifyEmail => l.guestVerifyEmail,
      GuestJoinEventKind.invalidCode => l.guestInvalidCode,
      GuestJoinEventKind.alreadyHasAccess => l.guestAlreadyHasAccess,
      GuestJoinEventKind.error => l.guestJoinFailed,
    };
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
