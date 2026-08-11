import 'dart:io';

import 'client_update_service.dart';
import 'update_provider.dart';

final class DirectFireUpdateProvider implements UpdateProvider {
  DirectFireUpdateProvider({required ClientVersion currentVersion})
    : _service = ClientUpdateService(currentVersion: currentVersion);

  final ClientUpdateService _service;

  @override
  DistributionChannel get channel => DistributionChannel.directFire;

  @override
  bool get supportsDirectInstall => true;

  @override
  Future<ClientUpdateRelease?> checkForUpdate() => _service.checkForUpdate();

  @override
  Future<File> downloadAndVerify(
    ClientUpdateRelease release, {
    DownloadProgress? onProgress,
  }) => _service.downloadAndVerify(release, onProgress: onProgress);

  @override
  Future<bool> canInstallPackages() => _service.canInstallPackages();

  @override
  Future<bool> openInstallPermission() => _service.openInstallPermission();

  @override
  Future<bool> installApk(File apk) => _service.installApk(apk);

  @override
  Future<bool> openStoreListing() async => false;

  @override
  void dispose() => _service.dispose();
}
