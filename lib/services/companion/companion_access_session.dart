import 'dart:convert';
import 'dart:math';

final class CompanionAccessSession {
  CompanionAccessSession._(this.token, this.expiresAt);

  factory CompanionAccessSession.create({
    Duration lifetime = const Duration(minutes: 10),
    Random? random,
  }) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(32, (_) => source.nextInt(256));
    return CompanionAccessSession._(
      base64Url.encode(bytes).replaceAll('=', ''),
      DateTime.now().toUtc().add(lifetime),
    );
  }

  final String token;
  final DateTime expiresAt;

  bool get isExpired => !DateTime.now().toUtc().isBefore(expiresAt);

  bool accepts(String candidate) {
    if (isExpired || candidate.length != token.length) return false;
    var difference = 0;
    for (var index = 0; index < token.length; index++) {
      difference |= token.codeUnitAt(index) ^ candidate.codeUnitAt(index);
    }
    return difference == 0;
  }
}
