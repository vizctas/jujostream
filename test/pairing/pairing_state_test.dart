import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/computer_details.dart';

/// Tests for the pairing state reconciliation logic.
///
/// These verify the rules that govern how poll results (from HTTPS/HTTP)
/// interact with the locally cached pairing state. The reconciliation
/// logic lives in ComputerProvider._addOrUpdateComputer, but we test
/// the state transitions in isolation here.

/// Simulates the reconciliation logic from _addOrUpdateComputer.
/// Returns the final (pairState, serverCert, pairStatusFromHttps).
({PairState pairState, String serverCert, bool pairStatusFromHttps})
    reconcile({
  required PairState incomingPairState,
  required bool incomingPairStatusFromHttps,
  required String incomingServerCert,
  required PairState existingPairState,
  required bool existingPairStatusFromHttps,
  required String existingServerCert,
  required bool inGracePeriod,
}) {
  // Copy incoming cert from existing if empty
  var serverCert = incomingServerCert;
  if (serverCert.isEmpty && existingServerCert.isNotEmpty) {
    serverCert = existingServerCert;
  }

  var pairState = incomingPairState;
  var pairStatusFromHttps = incomingPairStatusFromHttps;

  if (incomingPairStatusFromHttps) {
    if (incomingPairState == PairState.notPaired &&
        existingPairState == PairState.paired) {
      if (inGracePeriod) {
        pairState = PairState.paired;
        pairStatusFromHttps = true;
      } else {
        serverCert = '';
      }
    }
  } else if (incomingPairState == PairState.notPaired &&
      existingPairState == PairState.paired &&
      existingServerCert.isNotEmpty &&
      existingPairStatusFromHttps) {
    pairState = PairState.paired;
    pairStatusFromHttps = true;
  }

  return (
    pairState: pairState,
    serverCert: serverCert,
    pairStatusFromHttps: pairStatusFromHttps,
  );
}

/// Simulates verifyPairing decision logic.
/// Returns true if pairing should be considered valid.
bool verifyPairingDecision({
  required bool serverReachable,
  required PairState serverPairState,
  required bool serverPairStatusFromHttps,
  required bool inGracePeriod,
}) {
  if (!serverReachable) return true; // optimistic
  if (serverPairState == PairState.paired) return true;
  if (!serverPairStatusFromHttps) return true; // HTTP fallback — can't trust
  if (inGracePeriod) return true;
  return false; // HTTPS confirmed not paired, outside grace
}

void main() {
  group('Pairing State Reconciliation (_addOrUpdateComputer)', () {
    test('HTTPS paired=1 preserves paired state', () {
      final r = reconcile(
        incomingPairState: PairState.paired,
        incomingPairStatusFromHttps: true,
        incomingServerCert: '',
        existingPairState: PairState.paired,
        existingPairStatusFromHttps: true,
        existingServerCert: 'DEADBEEF',
        inGracePeriod: false,
      );
      expect(r.pairState, PairState.paired);
      expect(r.serverCert, 'DEADBEEF'); // preserved from existing
    });

    test('HTTPS paired=0 revokes pairing (outside grace period)', () {
      final r = reconcile(
        incomingPairState: PairState.notPaired,
        incomingPairStatusFromHttps: true,
        incomingServerCert: '',
        existingPairState: PairState.paired,
        existingPairStatusFromHttps: true,
        existingServerCert: 'DEADBEEF',
        inGracePeriod: false,
      );
      expect(r.pairState, PairState.notPaired);
      expect(r.serverCert, ''); // cleared
    });

    test('HTTPS paired=0 preserves pairing (inside grace period)', () {
      final r = reconcile(
        incomingPairState: PairState.notPaired,
        incomingPairStatusFromHttps: true,
        incomingServerCert: '',
        existingPairState: PairState.paired,
        existingPairStatusFromHttps: true,
        existingServerCert: 'DEADBEEF',
        inGracePeriod: true,
      );
      expect(r.pairState, PairState.paired);
      expect(r.serverCert, 'DEADBEEF'); // preserved
      expect(r.pairStatusFromHttps, true);
    });

    test('HTTP fallback (paired=0) preserves HTTPS-confirmed pairing', () {
      final r = reconcile(
        incomingPairState: PairState.notPaired,
        incomingPairStatusFromHttps: false, // HTTP fallback
        incomingServerCert: '',
        existingPairState: PairState.paired,
        existingPairStatusFromHttps: true,
        existingServerCert: 'DEADBEEF',
        inGracePeriod: false,
      );
      expect(r.pairState, PairState.paired);
      expect(r.serverCert, 'DEADBEEF');
      expect(r.pairStatusFromHttps, true);
    });

    test('HTTP fallback does NOT preserve non-HTTPS-confirmed pairing', () {
      final r = reconcile(
        incomingPairState: PairState.notPaired,
        incomingPairStatusFromHttps: false,
        incomingServerCert: '',
        existingPairState: PairState.paired,
        existingPairStatusFromHttps: false, // never confirmed via HTTPS
        existingServerCert: '',
        inGracePeriod: false,
      );
      expect(r.pairState, PairState.notPaired);
    });

    test('First discovery of unpaired server stays unpaired', () {
      final r = reconcile(
        incomingPairState: PairState.notPaired,
        incomingPairStatusFromHttps: true,
        incomingServerCert: '',
        existingPairState: PairState.notPaired,
        existingPairStatusFromHttps: false,
        existingServerCert: '',
        inGracePeriod: false,
      );
      expect(r.pairState, PairState.notPaired);
      expect(r.serverCert, '');
    });

    test('HTTPS paired=1 on previously unpaired server sets paired', () {
      final r = reconcile(
        incomingPairState: PairState.paired,
        incomingPairStatusFromHttps: true,
        incomingServerCert: '',
        existingPairState: PairState.notPaired,
        existingPairStatusFromHttps: false,
        existingServerCert: '',
        inGracePeriod: false,
      );
      expect(r.pairState, PairState.paired);
    });

    test('Grace period preserves serverCert from existing', () {
      final r = reconcile(
        incomingPairState: PairState.notPaired,
        incomingPairStatusFromHttps: true,
        incomingServerCert: '',
        existingPairState: PairState.paired,
        existingPairStatusFromHttps: true,
        existingServerCert: 'CAFEBABE',
        inGracePeriod: true,
      );
      // serverCert was copied from existing before reconciliation
      expect(r.serverCert, 'CAFEBABE');
      expect(r.pairState, PairState.paired);
    });
  });

  group('verifyPairing Decision Logic', () {
    test('server unreachable → allow entry (optimistic)', () {
      expect(
        verifyPairingDecision(
          serverReachable: false,
          serverPairState: PairState.notPaired,
          serverPairStatusFromHttps: false,
          inGracePeriod: false,
        ),
        true,
      );
    });

    test('HTTPS confirms paired → allow entry', () {
      expect(
        verifyPairingDecision(
          serverReachable: true,
          serverPairState: PairState.paired,
          serverPairStatusFromHttps: true,
          inGracePeriod: false,
        ),
        true,
      );
    });

    test('HTTP fallback says not paired → allow entry (can\'t trust HTTP)', () {
      expect(
        verifyPairingDecision(
          serverReachable: true,
          serverPairState: PairState.notPaired,
          serverPairStatusFromHttps: false,
          inGracePeriod: false,
        ),
        true,
      );
    });

    test('HTTPS says not paired, inside grace → allow entry', () {
      expect(
        verifyPairingDecision(
          serverReachable: true,
          serverPairState: PairState.notPaired,
          serverPairStatusFromHttps: true,
          inGracePeriod: true,
        ),
        true,
      );
    });

    test('HTTPS says not paired, outside grace → BLOCK entry', () {
      expect(
        verifyPairingDecision(
          serverReachable: true,
          serverPairState: PairState.notPaired,
          serverPairStatusFromHttps: true,
          inGracePeriod: false,
        ),
        false,
      );
    });
  });

  group('ComputerDetails Model', () {
    test('isPaired returns true only for PairState.paired', () {
      final c = ComputerDetails();
      expect(c.isPaired, false);
      c.pairState = PairState.paired;
      expect(c.isPaired, true);
      c.pairState = PairState.failed;
      expect(c.isPaired, false);
      c.pairState = PairState.alreadyInProgress;
      expect(c.isPaired, false);
    });

    test('isReachable returns true only for ComputerState.online', () {
      final c = ComputerDetails();
      expect(c.isReachable, false); // default is unknown
      c.state = ComputerState.online;
      expect(c.isReachable, true);
      c.state = ComputerState.offline;
      expect(c.isReachable, false);
    });

    test('toJson/fromJson roundtrip preserves all fields', () {
      final original = ComputerDetails(
        uuid: 'test-uuid',
        name: 'Test PC',
        localAddress: '192.168.1.100',
        remoteAddress: '1.2.3.4',
        manualAddress: '192.168.1.100',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        httpsPort: 47984,
        externalPort: 47989,
        serverCert: 'CAFEBABE',
        state: ComputerState.online,
        pairState: PairState.paired,
        runningGameId: 42,
        activeAddress: '192.168.1.100',
        serverVersion: '7.1.431.-1',
        gfeVersion: '3.27',
        serverCodecModeSupport: 15,
      );

      final json = original.toJson();
      final restored = ComputerDetails.fromJson(json);

      expect(restored.uuid, original.uuid);
      expect(restored.name, original.name);
      expect(restored.localAddress, original.localAddress);
      expect(restored.remoteAddress, original.remoteAddress);
      expect(restored.manualAddress, original.manualAddress);
      expect(restored.macAddress, original.macAddress);
      expect(restored.httpsPort, original.httpsPort);
      expect(restored.externalPort, original.externalPort);
      expect(restored.serverCert, original.serverCert);
      expect(restored.state, original.state);
      expect(restored.pairState, original.pairState);
      expect(restored.runningGameId, original.runningGameId);
      expect(restored.activeAddress, original.activeAddress);
      expect(restored.serverVersion, original.serverVersion);
      expect(restored.gfeVersion, original.gfeVersion);
      expect(restored.serverCodecModeSupport, original.serverCodecModeSupport);
    });

    test('pairStatusFromHttps is NOT serialized (runtime-only flag)', () {
      final c = ComputerDetails();
      c.pairStatusFromHttps = true;
      final json = c.toJson();
      expect(json.containsKey('pairStatusFromHttps'), false);
    });

    test('fromJson with missing fields uses safe defaults', () {
      final c = ComputerDetails.fromJson({});
      expect(c.uuid, '');
      expect(c.name, 'Unknown');
      expect(c.httpsPort, 47984);
      expect(c.externalPort, 47989);
      expect(c.pairState, PairState.notPaired);
      expect(c.state, ComputerState.unknown);
    });

    test('pairStatusFromHttps defaults to false', () {
      final c = ComputerDetails();
      expect(c.pairStatusFromHttps, false);
    });

    test('pairStatusFromHttps is reconstructed on load for paired+cert', () {
      // Simulates _loadPersistedComputers logic
      final c = ComputerDetails(
        pairState: PairState.paired,
        serverCert: 'DEADBEEF',
      );
      // This is what _loadPersistedComputers does:
      if (c.pairState == PairState.paired && c.serverCert.isNotEmpty) {
        c.pairStatusFromHttps = true;
      }
      expect(c.pairStatusFromHttps, true);
    });

    test('pairStatusFromHttps NOT reconstructed if no cert', () {
      final c = ComputerDetails(
        pairState: PairState.paired,
        serverCert: '',
      );
      if (c.pairState == PairState.paired && c.serverCert.isNotEmpty) {
        c.pairStatusFromHttps = true;
      }
      expect(c.pairStatusFromHttps, false);
    });
  });

  group('PairState Enum', () {
    test('all states have correct indices for serialization', () {
      expect(PairState.notPaired.index, 0);
      expect(PairState.paired.index, 1);
      expect(PairState.pinRequired.index, 2);
      expect(PairState.alreadyInProgress.index, 3);
      expect(PairState.failed.index, 4);
    });

    test('PairState.values roundtrip via index', () {
      for (final state in PairState.values) {
        expect(PairState.values[state.index], state);
      }
    });
  });
}
