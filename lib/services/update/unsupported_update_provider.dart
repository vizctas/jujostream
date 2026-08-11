import 'dart:io';

import 'update_models.dart';
import 'update_provider.dart';

final class UnsupportedUpdateProvider implements UpdateProvider {
  @override
  DistributionChannel get channel => DistributionChannel.unsupported;
  @override
  bool get supportsDirectInstall => false;
  @override
  Future<ClientUpdateRelease?> checkForUpdate() async => null;
  @override
  Future<File> downloadAndVerify(
    ClientUpdateRelease release, {
    DownloadProgress? onProgress,
  }) => throw UnsupportedError('No updater configured for this build');
  @override
  Future<bool> canInstallPackages() async => false;
  @override
  Future<bool> openInstallPermission() async => false;
  @override
  Future<bool> installApk(File apk) async => false;
  @override
  Future<bool> openStoreListing() async => false;
  @override
  void dispose() {}
}
