import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'update_models.dart';
export 'update_models.dart';

class ClientUpdateService {
  static const _repository = 'vizctas/Jujo.StreamServer.Releases';
  static const _maxApkBytes = 250 * 1024 * 1024;
  static const _channel = MethodChannel('com.jujostream/app_updater');
  static final _sha256Pattern = RegExp(r'^[a-fA-F0-9]{64}$');

  final ClientVersion currentVersion;
  final http.Client _client;

  ClientUpdateService({required this.currentVersion, http.Client? client})
    : _client = client ?? http.Client();

  Future<ClientUpdateRelease?> checkForUpdate() async {
    final uri = Uri.https('api.github.com', '/repos/$_repository/releases', {
      'per_page': '50',
    });
    final response = await _client
        .get(
          uri,
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'JUJO-Stream-Client',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'GitHub releases returned HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    final payload = jsonDecode(response.body);
    if (payload is! List) {
      throw const FormatException('Unexpected GitHub releases response');
    }
    return selectLatestRelease(payload, currentVersion);
  }

  static ClientUpdateRelease? selectLatestRelease(
    List<dynamic> releases,
    ClientVersion currentVersion,
  ) {
    ClientUpdateRelease? selected;
    for (final entry in releases) {
      if (entry is! Map) continue;
      if (entry['draft'] == true || entry['prerelease'] == true) continue;
      final tag = entry['tag_name']?.toString() ?? '';
      if (!tag.startsWith('client-')) continue;

      ClientVersion version;
      try {
        version = ClientVersion.parse(tag);
      } on FormatException {
        continue;
      }
      if (version.compareTo(currentVersion) <= 0) continue;

      final assets = entry['assets'];
      if (assets is! List) continue;
      Map? apkJson;
      for (final candidate in assets.whereType<Map>()) {
        final name = candidate['name']?.toString().toLowerCase() ?? '';
        if (name.endsWith('.apk') &&
            name.contains('android') &&
            !name.contains('debug')) {
          apkJson = candidate;
          break;
        }
      }
      if (apkJson == null) continue;
      final downloadUrl = Uri.tryParse(
        apkJson['browser_download_url']?.toString() ?? '',
      );
      final releasePage = Uri.tryParse(entry['html_url']?.toString() ?? '');
      if (downloadUrl == null || releasePage == null) continue;
      if (!_isAllowedReleasePage(releasePage) ||
          !_isAllowedDownloadUri(downloadUrl)) {
        continue;
      }

      final digest = apkJson['digest']?.toString();
      final digestHash = digest?.startsWith('sha256:') == true
          ? digest!.substring('sha256:'.length)
          : null;
      final release = ClientUpdateRelease(
        version: version,
        tag: tag,
        releasePage: releasePage,
        apk: ClientUpdateAsset(
          name: apkJson['name'].toString(),
          downloadUrl: downloadUrl,
          size: (apkJson['size'] as num?)?.toInt() ?? 0,
          sha256: _isValidSha256(digestHash) ? digestHash!.toLowerCase() : null,
        ),
      );
      if (selected == null || release.version.compareTo(selected.version) > 0) {
        selected = release;
      }
    }
    return selected;
  }

  Future<File> downloadAndVerify(
    ClientUpdateRelease release, {
    DownloadProgress? onProgress,
  }) async {
    final expectedHash =
        release.apk.sha256 ?? await _fetchChecksum(release, release.apk.name);
    if (!_isValidSha256(expectedHash)) {
      throw const FormatException('Release does not provide a valid SHA-256');
    }

    final request = http.Request('GET', release.apk.downloadUrl)
      ..headers.addAll(const {'User-Agent': 'JUJO-Stream-Client'});
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 20));
    final finalUri = response.request?.url ?? release.apk.downloadUrl;
    if (!_isAllowedDownloadUri(finalUri)) {
      throw FormatException('APK download redirected to an untrusted host');
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'APK download returned HTTP ${response.statusCode}',
        uri: release.apk.downloadUrl,
      );
    }

    final directory = await getTemporaryDirectory();
    final destination = File('${directory.path}/${release.apk.name}');
    final sink = destination.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > _maxApkBytes ||
            (release.apk.size > 0 && received > release.apk.size)) {
          throw const FormatException('APK download exceeded expected size');
        }
        sink.add(chunk);
        onProgress?.call(received, response.contentLength ?? release.apk.size);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      try {
        await destination.delete();
      } catch (_) {}
      rethrow;
    }

    if (release.apk.size > 0 && received != release.apk.size) {
      try {
        await destination.delete();
      } catch (_) {}
      throw const FormatException('APK download size does not match release');
    }

    final actualHash = (await sha256.bind(destination.openRead()).first)
        .toString()
        .toLowerCase();
    if (actualHash != expectedHash!.toLowerCase()) {
      try {
        await destination.delete();
      } catch (_) {}
      throw const FormatException('Downloaded APK failed SHA-256 verification');
    }
    return destination;
  }

  Future<String?> _fetchChecksum(
    ClientUpdateRelease release,
    String apkName,
  ) async {
    final uri = Uri.parse(
      'https://github.com/$_repository/releases/download/'
      '${release.tag}/SHA256SUMS.txt',
    );
    final response = await _client
        .get(uri, headers: const {'User-Agent': 'JUJO-Stream-Client'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.ok) return null;
    for (final line in const LineSplitter().convert(response.body)) {
      final match = RegExp(r'^([a-fA-F0-9]{64})\s+\*?(.+)$').firstMatch(line);
      if (match != null && match.group(2)!.trim() == apkName) {
        return match.group(1)!.toLowerCase();
      }
    }
    return null;
  }

  Future<bool> canInstallPackages() async {
    return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
  }

  Future<bool> openInstallPermission() async {
    return await _channel.invokeMethod<bool>('openInstallPermission') ?? false;
  }

  Future<bool> installApk(File apk) async {
    return await _channel.invokeMethod<bool>('installApk', {
          'path': apk.path,
        }) ??
        false;
  }

  static bool _isValidSha256(String? value) {
    return value != null && _sha256Pattern.hasMatch(value);
  }

  static bool _isAllowedReleasePage(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == 'github.com' &&
      uri.path.startsWith('/$_repository/releases/');

  static bool _isAllowedDownloadUri(Uri uri) {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) return false;
    if (uri.host == 'github.com') {
      return uri.path.startsWith('/$_repository/releases/download/');
    }
    return uri.host == 'objects.githubusercontent.com' ||
        uri.host.endsWith('.githubusercontent.com');
  }

  void dispose() => _client.close();
}
