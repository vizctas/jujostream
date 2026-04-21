import re

with open('lib/services/pairing/pairing_service.dart', 'r') as f:
    content = f.read()

old_phase1 = """      final phase1Response = await _freshGet(phase1Url);

      if (phase1Response.statusCode != 200) {
        return PairingResult.failed(
          'Phase 1 failed: HTTP ${phase1Response.statusCode}',
        );
      }"""

new_phase1 = """      var phase1Response = await _freshGet(phase1Url);

      if (phase1Response.statusCode != 200) {
        _log.w('Phase 1 failed (${phase1Response.statusCode}). Server might be stuck in a previous session. Retrying to clear state...');
        await Future.delayed(const Duration(milliseconds: 500));
        phase1Response = await _freshGet(phase1Url);
        if (phase1Response.statusCode != 200) {
          return PairingResult.failed(
            'Phase 1 failed: HTTP ${phase1Response.statusCode}',
          );
        }
      }"""

content = content.replace(old_phase1, new_phase1)

with open('lib/services/pairing/pairing_service.dart', 'w') as f:
          e(content)
