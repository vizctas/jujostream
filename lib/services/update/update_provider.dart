import 'dart:io';

import 'update_models.dart';

enum DistributionChannel { play, directFire, unsupported }

abstract interface class UpdateProvider {
  DistributionChannel get channel;
  bool get supportsDirectInstall;
  Future<ClientUpdateRelease?> checkForUpdate();
  Future<File> downloadAndVerify(
    ClientUpdateRelease release, {
    DownloadProgress? onProgress,
  });
  Future<bool> canInstallPackages();
  Future<bool> openInstallPermission();
  Future<bool> installApk(File apk);
  Future<bool> openStoreListing();
  void dispose();
}
