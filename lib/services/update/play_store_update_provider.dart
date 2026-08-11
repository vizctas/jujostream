import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'update_models.dart';
import 'update_provider.dart';

final class PlayStoreUpdateProvider implements UpdateProvider {
  static final Uri _listing = Uri.parse(
    'https://play.google.com/store/apps/details?id=com.vizcorp.moonlight_jujo_stream',
  );

  @override
  DistributionChannel get channel => DistributionChannel.play;

  @override
  bool get supportsDirectInstall => false;

  @override
  Future<ClientUpdateRelease?> checkForUpdate() async => null;

  @override
  Future<File> downloadAndVerify(
    ClientUpdateRelease release, {
    DownloadProgress? onProgress,
  }) => throw UnsupportedError('Play builds cannot download APK updates');

  @override
  Future<bool> canInstallPackages() async => false;

  @override
  Future<bool> openInstallPermission() async => false;

  @override
  Future<bool> installApk(File apk) async => false;

  @override
  Future<bool> openStoreListing() =>
      launchUrl(_listing, mode: LaunchMode.externalApplication);

  @override
  void dispose() {}
}
