import '../models/computer_details.dart';

enum ComputerConnectionStatus {
  unpaired,
  localPaired,
  cloudConnected,
  localPairedCloudDisconnected,
}

ComputerConnectionStatus computerConnectionStatus(
  ComputerDetails computer, {
  required bool cloudSignedIn,
}) {
  if (!computer.isPaired) return ComputerConnectionStatus.unpaired;
  if (!computer.isCloud) return ComputerConnectionStatus.localPaired;
  return cloudSignedIn
      ? ComputerConnectionStatus.cloudConnected
      : ComputerConnectionStatus.localPairedCloudDisconnected;
}

String computerConnectionStatusLabel(
  ComputerConnectionStatus status, {
  required bool isSpanish,
}) {
  return switch (status) {
    ComputerConnectionStatus.unpaired =>
      isSpanish ? 'Sin emparejar' : 'Not paired',
    ComputerConnectionStatus.localPaired =>
      isSpanish ? 'Emparejado localmente' : 'Paired locally',
    ComputerConnectionStatus.cloudConnected =>
      isSpanish
          ? 'Emparejado · JUJO.Cloud conectado'
          : 'Paired · JUJO.Cloud connected',
    ComputerConnectionStatus.localPairedCloudDisconnected =>
      isSpanish
          ? 'Emparejado localmente · Cloud desconectado'
          : 'Paired locally · Cloud disconnected',
  };
}
