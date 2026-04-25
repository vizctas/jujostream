/// Centralized error code system for JUJO Stream.
///
/// User-facing messages show only the short code (e.g., "PAIR-001").
/// Developer-facing descriptions are in [errorDescriptions].
/// Raw exception details are stripped of sensitive data (IPs, hashes, URLs).
library;

/// Classifies a raw error string into a short, user-friendly error code.
///
/// Returns a record with the code and a safe user message.
({String code, String userMessage}) classifyError(
  String category,
  dynamic rawError,
) {
  final raw = rawError.toString();
  final entry = _matchError(category, raw);
  return (
    code: entry.code,
    userMessage: '${entry.code}: ${entry.shortMessage}',
  );
}

/// Same as [classifyError] but with locale support.
({String code, String userMessage}) classifyErrorLocalized(
  String category,
  dynamic rawError, {
  bool isSpanish = false,
}) {
  final raw = rawError.toString();
  final entry = _matchError(category, raw);
  final msg = isSpanish ? entry.shortMessageEs : entry.shortMessage;
  return (
    code: entry.code,
    userMessage: '${entry.code}: $msg',
  );
}

/// Strips sensitive data from error strings: URLs, IPs, uniqueIds, hashes.
String sanitizeError(String raw) {
  var s = raw;
  // Strip full URLs
  s = s.replaceAll(RegExp(r'https?://[^\s,)]+'), '[URL]');
  // Strip uniqueid values
  s = s.replaceAll(RegExp(r'uniqueid=[a-fA-F0-9-]+'), 'uniqueid=[REDACTED]');
  // Strip long hex strings (certs, hashes)
  s = s.replaceAll(RegExp(r'[a-fA-F0-9]{32,}'), '[HASH]');
  // Strip IP:port patterns
  s = s.replaceAll(
    RegExp(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?'),
    '[HOST]',
  );
  return s;
}

/// Developer-facing error dictionary. Maps code → full technical description.
const Map<String, String> errorDescriptions = {
  'PAIR-001': 'Connection abort during pairing HTTP request. '
      'ClientException: Software caused connection abort. '
      'Typically: server not reachable, firewall blocking port, or server crashed mid-handshake.',
  'PAIR-002': 'Connection refused by server during pairing. '
      'Server is not running or port is wrong.',
  'PAIR-003': 'Pairing request timed out. '
      'Server did not respond within the timeout window. '
      'Network latency, firewall, or server overloaded.',
  'PAIR-004': 'Server rejected pairing request (wrong PIN or pairing already in progress).',
  'PAIR-005': 'No server certificate returned. '
      'Another pairing session may already be active on the server.',
  'PAIR-006': 'Server rejected challenge — PIN incorrect or pairing state invalid.',
  'PAIR-007': 'Server rejected client pairing secret after handshake. '
      'Check Sunshine/Apollo logs.',
  'PAIR-008': 'Malformed server response during pairing handshake.',
  'PAIR-009': 'DNS resolution failed for server hostname.',
  'PAIR-010': 'TLS/SSL handshake error during pairing.',
  'PAIR-099': 'Unknown pairing error. See raw logs for details.',

  'STRM-001': 'Stream connection failed — server returned non-zero status code.',
  'STRM-002': 'Stream timed out during startup (30s). '
      'Server may be overloaded or network too slow.',
  'STRM-003': 'GS_WRONG_STATE (104) — server has a stale session from a previous client.',
  'STRM-004': 'Texture creation failed on Android. '
      'GPU driver issue or out of memory.',
  'STRM-005': 'Video decoder failed to initialize. '
      'Codec not supported by device hardware.',
  'STRM-099': 'Unknown streaming error. See raw logs for details.',

  'NET-001': 'Connection abort — TCP reset by peer or OS.',
  'NET-002': 'Connection refused — target host actively rejected the connection.',
  'NET-003': 'Connection timed out — no response from host.',
  'NET-004': 'DNS resolution failed.',
  'NET-005': 'Network unreachable — no route to host.',
  'NET-099': 'Unknown network error.',

  'DISC-001': 'mDNS discovery failed — no multicast support on this network.',
  'DISC-002': 'Server responded to discovery but returned invalid XML.',
  'DISC-099': 'Unknown discovery error.',
};

class _ErrorEntry {
  final String code;
  final String shortMessage;
  final String shortMessageEs;
  const _ErrorEntry(this.code, this.shortMessage, this.shortMessageEs);
}

_ErrorEntry _matchError(String category, String raw) {
  final lower = raw.toLowerCase();

  if (category == 'PAIR' || category == 'pair') {
    if (lower.contains('connection abort') ||
        lower.contains('software caused connection')) {
      return const _ErrorEntry(
        'PAIR-001',
        'Connection lost during pairing',
        'Conexión perdida durante el emparejamiento',
      );
    }
    if (lower.contains('connection refused')) {
      return const _ErrorEntry(
        'PAIR-002',
        'Server refused the connection',
        'El servidor rechazó la conexión',
      );
    }
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return const _ErrorEntry(
        'PAIR-003',
        'Pairing timed out',
        'Tiempo de espera agotado',
      );
    }
    if (lower.contains('rejected pairing') ||
        lower.contains('wrong pin')) {
      return const _ErrorEntry(
        'PAIR-004',
        'Wrong PIN or server rejected pairing',
        'PIN incorrecto o el servidor rechazó el emparejamiento',
      );
    }
    if (lower.contains('no server certificate') ||
        lower.contains('already in progress')) {
      return const _ErrorEntry(
        'PAIR-005',
        'Another pairing session is active',
        'Otra sesión de emparejamiento está activa',
      );
    }
    if (lower.contains('rejected challenge') ||
        lower.contains('rejected secret') ||
        lower.contains('pin incorrect')) {
      return const _ErrorEntry(
        'PAIR-006',
        'PIN verification failed',
        'Verificación de PIN fallida',
      );
    }
    if (lower.contains('rejected client pairing')) {
      return const _ErrorEntry(
        'PAIR-007',
        'Server rejected pairing after handshake',
        'El servidor rechazó el emparejamiento después del handshake',
      );
    }
    if (lower.contains('malformed') || lower.contains('invalid pairing secret')) {
      return const _ErrorEntry(
        'PAIR-008',
        'Malformed server response',
        'Respuesta del servidor malformada',
      );
    }
    if (lower.contains('host not found') ||
        lower.contains('no address associated') ||
        lower.contains('getaddrinfo') ||
        lower.contains('dns')) {
      return const _ErrorEntry(
        'PAIR-009',
        'Server not found (DNS error)',
        'Servidor no encontrado (error DNS)',
      );
    }
    if (lower.contains('handshake') || lower.contains('ssl') || lower.contains('tls')) {
      return const _ErrorEntry(
        'PAIR-010',
        'Secure connection failed',
        'Conexión segura fallida',
      );
    }
    if (lower.contains('phase') && lower.contains('failed')) {
      return const _ErrorEntry(
        'PAIR-008',
        'Pairing handshake failed',
        'Handshake de emparejamiento fallido',
      );
    }
    return const _ErrorEntry(
      'PAIR-099',
      'Pairing failed (unknown error)',
      'Emparejamiento fallido (error desconocido)',
    );
  }

  if (category == 'STRM' || category == 'stream') {
    if (lower.contains('wrong_state') || lower.contains('code 104')) {
      return const _ErrorEntry(
        'STRM-003',
        'Stale session detected',
        'Sesión anterior detectada',
      );
    }
    if (lower.contains('texture') || lower.contains('surface')) {
      return const _ErrorEntry(
        'STRM-004',
        'Video surface creation failed',
        'Creación de superficie de video fallida',
      );
    }
    if (lower.contains('codec') || lower.contains('decoder')) {
      return const _ErrorEntry(
        'STRM-005',
        'Video decoder error',
        'Error del decodificador de video',
      );
    }
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return const _ErrorEntry(
        'STRM-002',
        'Stream startup timed out',
        'Tiempo de espera del stream agotado',
      );
    }
    return const _ErrorEntry(
      'STRM-099',
      'Stream error (unknown)',
      'Error de stream (desconocido)',
    );
  }

  // Generic network errors
  if (lower.contains('connection abort') ||
      lower.contains('software caused connection')) {
    return const _ErrorEntry(
      'NET-001',
      'Connection aborted',
      'Conexión abortada',
    );
  }
  if (lower.contains('connection refused')) {
    return const _ErrorEntry(
      'NET-002',
      'Connection refused',
      'Conexión rechazada',
    );
  }
  if (lower.contains('timed out') || lower.contains('timeout')) {
    return const _ErrorEntry(
      'NET-003',
      'Connection timed out',
      'Tiempo de conexión agotado',
    );
  }

  return const _ErrorEntry(
    'ERR-999',
    'Unexpected error',
    'Error inesperado',
  );
}
