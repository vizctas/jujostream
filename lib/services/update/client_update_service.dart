import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ClientVersion implements Comparable<ClientVersion> {
  final int major;
  final int minor;
  final int patch;

  const ClientVersion(this.major, this.minor, this.patch);

  factory ClientVersion.parse(String value) {
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(value);
    if (match == null) {
      throw FormatException('Invalid client version: $value');
    }
    return ClientVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  @override
  int compareTo(ClientVersion other) {
    final majorResult = major.compareTo(other.major);
    if (majorResult != 0) return majorResult;
    final minorResult = minor.compareTo(other.minor);
    if (minorResult != 0) return minorResult;
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

class ClientUpdateAsset {
  final String name;
  final Uri downloadUrl;
  final int size;
  final String? sha256;

  const ClientUpdateAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    this.sha256,
  });
}

class ClientUpdateRelease {
  final ClientVersion version;
  final String tag;
  final ClientUpdateAsset apk;
  final Uri releasePage;

  const ClientUpdateRelease({
    required this.version,
    required this.tag,
    required this.apk,
    required this.releasePage,
  });
}

typedef DownloadProgress = void Function(int received, int total);

class ClientUpdateService {
  static const _repository = 'vizctas/Jujo.StreamServer.Releases';
  static const _channel = MethodChannel('com.jujostream/app_updater');
  static final _sha256Pattern = RegExp(r'^[a-fA-F0-9]{64}$');

  final ClientVersion currentVersion;
  final http.Client _client;

  ClientUpdateService({
    required this.currentVersion,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<ClientUpdateRelease?> checkForUpdate() async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/$_repository/releases',
      {'per_page': '50'},
    );
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
      if (selected == null ||
          release.version.compareTo(selected.version) > 0) {
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

    final actualHash =
        (await sha256.bind(destination.openRead()).first).toString().toLowerCase();
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
    return await _channel.invokeMethod<bool>(
          'installApk',
          {'path': apk.path},
        ) ??
        false;
  }

  static bool _isValidSha256(String? value) {
    return value != null && _sha256Pattern.hasMatch(value);
  }

  void dispose() => _client.close();
}
