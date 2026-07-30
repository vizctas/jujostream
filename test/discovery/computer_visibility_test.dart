import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/computer_details.dart';
import 'package:jujostream/providers/computer_provider.dart';

void main() {
  test('signed-out users see a cloud server only while it is live on LAN', () {
    final cloudComputer = ComputerDetails(isCloud: true);

    expect(
      isComputerVisible(
        computer: cloudComputer,
        cloudSignedIn: false,
        lanDiscovered: false,
      ),
      isFalse,
    );
    expect(
      isComputerVisible(
        computer: cloudComputer,
        cloudSignedIn: false,
        lanDiscovered: true,
      ),
      isTrue,
    );
  });

  // The pinned pairing certificate is the authority, not the cloud session.
  // Visibility must not depend on the *shape* of the saved address: requiring
  // an RFC1918 literal hid servers reached over mDNS `.local`, IPv6, Tailscale
  // or link-local from a user standing right next to them.
  for (final address in const [
    '192.168.3.6',
    'living-room.local',
    'fd00::1',
    '100.83.4.19', // Tailscale CGNAT
    '203.0.113.7', // public
  ]) {
    test('signed-out users retain a paired server at $address', () {
      final cloudComputer = ComputerDetails(
        isCloud: true,
        localAddress: address,
        serverCert: 'pinned-server-cert',
      )..pairState = PairState.paired;

      expect(
        isComputerVisible(
          computer: cloudComputer,
          cloudSignedIn: false,
          lanDiscovered: false,
        ),
        isTrue,
      );
    });
  }

  test('an unpaired Cloud server still needs a session or LAN discovery', () {
    // No certificate means nothing to fall back on — the cloud is the only way
    // this device could reach it.
    final cloudComputer = ComputerDetails(
      isCloud: true,
      localAddress: '192.168.3.6',
    );

    expect(
      isComputerVisible(
        computer: cloudComputer,
        cloudSignedIn: false,
        lanDiscovered: false,
      ),
      isFalse,
    );
  });
}
