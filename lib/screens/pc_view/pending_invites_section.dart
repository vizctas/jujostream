import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/sync/cloud_sync_service.dart';
import '../../services/sync/guest_link.dart';

class PendingInvitesSection extends StatefulWidget {
  final List<CloudPendingInvite> invites;
  final bool isLoading;
  final Color accent;
  final bool isLight;
  final Future<bool> Function(CloudPendingInvite invite, {required bool accept})
  onRespond;
  final void Function(CloudPendingInvite invite, bool accepted, bool ok)?
  onResult;

  /// My join request awaiting the host's approval.
  final GuestRedeemResult? waiting;
  final VoidCallback? onCancelWaiting;

  /// Shows the "join with code" entry when set.
  final Future<void> Function(String code)? onJoinWithCode;

  const PendingInvitesSection({
    super.key,
    required this.invites,
    required this.isLoading,
    required this.accent,
    required this.isLight,
    required this.onRespond,
    this.onResult,
    this.waiting,
    this.onCancelWaiting,
    this.onJoinWithCode,
  });

  @override
  State<PendingInvitesSection> createState() => _PendingInvitesSectionState();
}

class _PendingInvitesSectionState extends State<PendingInvitesSection> {
  String? _busyInviteId;
  bool _busyAccept = false;

  Future<void> _respond(CloudPendingInvite invite, bool accept) async {
    if (_busyInviteId != null) return;
    setState(() {
      _busyInviteId = invite.inviteId;
      _busyAccept = accept;
    });
    var ok = false;
    try {
      ok = await widget.onRespond(invite, accept: accept);
    } finally {
      if (mounted) {
        setState(() => _busyInviteId = null);
      }
    }
    widget.onResult?.call(invite, accept, ok);
  }

  Future<void> _joinWithCode() async {
    final l = AppLocalizations.of(context);
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(l.guestJoinWithCode),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(hintText: l.guestCodeHint),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(l.guestJoinWithCode),
            ),
          ],
        );
      },
    );
    if (code != null && code.trim().isNotEmpty) {
      await widget.onJoinWithCode?.call(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading &&
        widget.invites.isEmpty &&
        widget.waiting == null &&
        widget.onJoinWithCode == null) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final fg = widget.isLight ? Colors.black87 : Colors.white;
    final sub = widget.isLight ? Colors.black54 : Colors.white60;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(
                Icons.mail_outline_rounded,
                size: 16,
                color: widget.invites.isNotEmpty ? Colors.tealAccent : sub,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.coopInvites,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (widget.isLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.accent,
                  ),
                ),
              if (widget.onJoinWithCode != null) ...[
                const SizedBox(width: 8),
                _InviteButton(
                  label: l.guestJoinWithCode,
                  color: fg,
                  fillColor: Colors.transparent,
                  borderColor: widget.isLight ? Colors.black12 : Colors.white24,
                  loading: false,
                  onTap: _joinWithCode,
                ),
              ],
            ],
          ),
        ),
        if (widget.waiting != null)
          _WaitingCard(
            waiting: widget.waiting!,
            isLight: widget.isLight,
            onCancel: widget.onCancelWaiting,
          ),
        for (final invite in widget.invites)
          _InviteCard(
            invite: invite,
            accent: widget.accent,
            isLight: widget.isLight,
            busy: _busyInviteId == invite.inviteId,
            busyAccept: _busyAccept,
            disabled: _busyInviteId != null,
            onAccept: () => _respond(invite, true),
            onDecline: () => _respond(invite, false),
          ),
      ],
    );
  }
}

class _WaitingCard extends StatelessWidget {
  final GuestRedeemResult waiting;
  final bool isLight;
  final VoidCallback? onCancel;

  const _WaitingCard({
    required this.waiting,
    required this.isLight,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final fg = isLight ? Colors.black87 : Colors.white;
    final sub = isLight ? Colors.black54 : Colors.white60;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLight
            ? Colors.black.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  waiting.serverName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l.guestWaiting,
                  style: TextStyle(color: sub, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _InviteButton(
            label: l.cancel,
            color: sub,
            fillColor: Colors.transparent,
            borderColor: isLight ? Colors.black12 : Colors.white24,
            loading: false,
            onTap: onCancel,
          ),
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  final CloudPendingInvite invite;
  final Color accent;
  final bool isLight;
  final bool busy;
  final bool busyAccept;
  final bool disabled;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _InviteCard({
    required this.invite,
    required this.accent,
    required this.isLight,
    required this.busy,
    required this.busyAccept,
    required this.disabled,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final fg = isLight ? Colors.black87 : Colors.white;
    final sub = isLight ? Colors.black54 : Colors.white60;
    final tagColor = invite.isCoop ? Colors.tealAccent : Colors.blueAccent;
    final metaParts = <String>[
      if (invite.ownerEmail.isNotEmpty) invite.ownerEmail,
      l.coopRoleLabel(invite.role),
      if (invite.isCoop && invite.expiresAt != null)
        l.coopExpiresIn(invite.expiresAt!),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLight
            ? Colors.black.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tagColor.withValues(alpha: isLight ? 0.35 : 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invite.serverName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  invite.isCoop ? l.coopInviteTempTag : l.coopInvitePermTag,
                  style: TextStyle(
                    color: isLight ? fg : tagColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (metaParts.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              metaParts.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: sub, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _InviteButton(
                label: l.decline,
                color: sub,
                fillColor: Colors.transparent,
                borderColor: isLight ? Colors.black12 : Colors.white24,
                loading: busy && !busyAccept,
                onTap: disabled ? null : onDecline,
              ),
              const SizedBox(width: 8),
              _InviteButton(
                label: l.accept,
                color: Colors.white,
                fillColor: accent,
                borderColor: accent,
                loading: busy && busyAccept,
                onTap: disabled ? null : onAccept,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InviteButton extends StatefulWidget {
  final String label;
  final Color color;
  final Color fillColor;
  final Color borderColor;
  final bool loading;
  final VoidCallback? onTap;

  const _InviteButton({
    required this.label,
    required this.color,
    required this.fillColor,
    required this.borderColor,
    required this.loading,
    required this.onTap,
  });

  @override
  State<_InviteButton> createState() => _InviteButtonState();
}

class _InviteButtonState extends State<_InviteButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: widget.onTap != null,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent || widget.onTap == null) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select) {
          widget.onTap!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: widget.fillColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? Colors.white : widget.borderColor,
              width: _focused ? 1.8 : 1,
            ),
          ),
          child: widget.loading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.color,
                  ),
                )
              : Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}
