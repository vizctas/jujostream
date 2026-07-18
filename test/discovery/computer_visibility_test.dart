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

  test('signed-out users retain a paired server at a private LAN address', () {
    final cloudComputer = ComputerDetails(
      isCloud: true,
      localAddress: '192.168.3.6',
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

  test('signed-out users do not retain a remote-only Cloud server', () {
    final cloudComputer = ComputerDetails(
      isCloud: true,
      localAddress: '203.0.113.7',
      serverCert: 'pinned-server-cert',
    )..pairState = PairState.paired;

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
