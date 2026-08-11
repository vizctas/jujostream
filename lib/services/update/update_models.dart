import 'dart:io';

class ClientVersion implements Comparable<ClientVersion> {
  final int major;
  final int minor;
  final int patch;

  const ClientVersion(this.major, this.minor, this.patch);

  factory ClientVersion.parse(String value) {
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(value);
    if (match == null) throw FormatException('Invalid client version: $value');
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
  const ClientUpdateAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    this.sha256,
  });

  final String name;
  final Uri downloadUrl;
  final int size;
  final String? sha256;
}

class ClientUpdateRelease {
  const ClientUpdateRelease({
    required this.version,
    required this.tag,
    required this.apk,
    required this.releasePage,
  });

  final ClientVersion version;
  final String tag;
  final ClientUpdateAsset apk;
  final Uri releasePage;
}

typedef DownloadProgress = void Function(int received, int total);

abstract interface class DownloadedUpdateInstaller {
  Future<bool> install(File apk);
}
