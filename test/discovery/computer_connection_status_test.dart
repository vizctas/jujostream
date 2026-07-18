import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/computer_details.dart';
import 'package:jujostream/ui/computer_connection_status.dart';

void main() {
  test('labels paired Cloud servers according to Cloud session state', () {
    final cloudServer = ComputerDetails(isCloud: true)
      ..pairState = PairState.paired;

    expect(
      computerConnectionStatus(cloudServer, cloudSignedIn: true),
      ComputerConnectionStatus.cloudConnected,
    );
    expect(
      computerConnectionStatus(cloudServer, cloudSignedIn: false),
      ComputerConnectionStatus.localPairedCloudDisconnected,
    );
  });

  test('labels non-Cloud pairing as local', () {
    final localServer = ComputerDetails()..pairState = PairState.paired;

    expect(
      computerConnectionStatus(localServer, cloudSignedIn: false),
      ComputerConnectionStatus.localPaired,
    );
  });
}
