/// Guest invite links: `jujostream://invite/XXXXX-XXXXX` and the
/// `redeem_guest_link` / `pending_guest_requests` payloads.
library;

/// Normalises a typed or linked code to `XXXXX-XXXXX`; null when it is not one.
String? normalizeGuestCode(String raw) {
  final clean = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (clean.length != 10) return null;
  return '${clean.substring(0, 5)}-${clean.substring(5)}';
}

/// Code carried by a `jujostream://invite/…` link; null for anything else.
/// The code is a path segment: supabase_flutter treats any deep link with a
/// `code` query parameter as a PKCE auth callback.
String? guestCodeFromLink(String link) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null || uri.scheme != 'jujostream' || uri.host != 'invite') {
    return null;
  }
  return uri.pathSegments.length == 1
      ? normalizeGuestCode(uri.pathSegments.single)
      : null;
}

/// Share text, identical to the one StreamAdmin produces.
String guestLinkShareText({
  required String serverName,
  required String code,
  required DateTime expiresAt,
}) {
  final local = expiresAt.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return 'Únete a mi partida en $serverName con Jujo.Stream\n'
      'jujostream://invite/$code\n'
      'Código: $code (válido hasta $hh:$mm)';
}

enum GuestRedeemOutcome {
  active,
  requested,
  verifyEmail,
  invalidOrExpired,
  alreadyHasAccess,
  error,
}

class GuestRedeemResult {
  final GuestRedeemOutcome outcome;
  final String inviteId;
  final String serverUrl;
  final String serverName;
  final String role;
  final DateTime? expiresAt;

  const GuestRedeemResult(
    this.outcome, {
    this.inviteId = '',
    this.serverUrl = '',
    this.serverName = '',
    this.role = 'coop_pad',
    this.expiresAt,
  });

  /// Maps the `redeem_guest_link` JSON (`{success,status,…}` or `{error}`).
  factory GuestRedeemResult.fromRpc(Map<String, dynamic> json) {
    if (json['success'] != true) {
      return GuestRedeemResult(switch (json['error']) {
        'verify_email' => GuestRedeemOutcome.verifyEmail,
        'invalid_or_expired' => GuestRedeemOutcome.invalidOrExpired,
        'already_has_access' => GuestRedeemOutcome.alreadyHasAccess,
        _ => GuestRedeemOutcome.error,
      });
    }
    final outcome = switch (json['status']) {
      'active' => GuestRedeemOutcome.active,
      'requested' => GuestRedeemOutcome.requested,
      _ => GuestRedeemOutcome.error,
    };
    final url = (json['server_url'] ?? '').toString().trim();
    final name = (json['server_name'] ?? '').toString().trim();
    return GuestRedeemResult(
      outcome,
      inviteId: (json['id'] ?? '').toString().trim(),
      serverUrl: url,
      serverName: name.isNotEmpty ? name : url,
      role: (json['role'] ?? 'coop_pad').toString(),
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())?.toUtc()
          : null,
    );
  }
}

/// A guest waiting for a manager's approval (`pending_guest_requests` row).
class GuestRequest {
  final String id;
  final String serverUrl;
  final String guestEmail;
  final String role;
  final DateTime? expiresAt;

  const GuestRequest({
    required this.id,
    required this.serverUrl,
    required this.guestEmail,
    required this.role,
    this.expiresAt,
  });

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now().toUtc());

  factory GuestRequest.fromJson(Map<String, dynamic> json) => GuestRequest(
    id: (json['id'] ?? '').toString().trim(),
    serverUrl: (json['server_url'] ?? '').toString().trim(),
    guestEmail: (json['guest_email'] ?? '').toString().trim(),
    role: (json['role'] ?? 'coop_pad').toString().trim(),
    expiresAt: json['expires_at'] != null
        ? DateTime.tryParse(json['expires_at'].toString())?.toUtc()
        : null,
  );
}
