import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/computer_details.dart';
import 'package:jujostream/services/http_api/nv_http_client.dart';

void main() {
  test('server ABR capability is parsed and persisted', () {
    final client = NvHttpClient();
    addTearDown(client.dispose);

    final computer = client.parseServerInfo(
      '<root><hostname>Host</hostname><ServerAbrActive>true</ServerAbrActive></root>',
      '192.0.2.1',
      47989,
    );

    expect(computer.serverAbrActive, isTrue);
    expect(ComputerDetails.fromJson(computer.toJson()).serverAbrActive, isTrue);
  });

  test('older servers keep client ABR ownership', () {
    final client = NvHttpClient();
    addTearDown(client.dispose);

    final computer = client.parseServerInfo(
      '<root><hostname>Host</hostname></root>',
      '192.0.2.1',
      47989,
    );

    expect(computer.serverAbrActive, isFalse);
  });
}
