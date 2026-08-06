import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../diagnostics_logger.dart';

/// A word challenge as the pairing client sees it: the shuffled candidates and
/// how many to pick, never which ones.
class WatchwordChallenge {
  const WatchwordChallenge({
    required this.challengeId,
    required this.words,
    required this.wordCount,
    required this.round,
    required this.maxRounds,
    required this.remainingSeconds,
    required this.locked,
  });

  final String challengeId;

  /// The N shuffled candidates. The K secret ones are in here somewhere.
  final List<String> words;

  /// How many words to select, in order.
  final int wordCount;

  final int round;
  final int maxRounds;
  final int remainingSeconds;

  /// True while the server is serving out a penalty wait.
  final bool locked;
}

/// Client half of Consigna / Watchword pairing.
///
/// The server holds K secret words and shows N candidates. The answer never
/// travels: the selected words are folded into the same salted hash the
/// existing `otpauth` pairing path already validates.
class WatchwordService {
  WatchwordService({HttpClient? httpClient})
    : _client = httpClient ?? (HttpClient()..connectionTimeout = const Duration(seconds: 5));

  final HttpClient _client;
  final _log = diagnosticsLogger('Watchword');

  /// Fetches the candidate words.
  ///
  /// [begin] tells the server that a user is answering, which pauses rotation
  /// so the words cannot change mid-selection. Send it only when the user has
  /// actually opened the grid.
  Future<WatchwordChallenge?> fetchChallenge({
    required String address,
    required int port,
    required String uniqueId,
    bool begin = false,
  }) async {
    final uri = Uri.parse(
      'http://$address:$port/watchword'
      '?uniqueid=$uniqueId${begin ? '&begin=1' : ''}',
    );

    try {
      final request = await _client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 6));
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        _log.w('Challenge fetch failed: HTTP ${response.statusCode}');
        return null;
      }

      final status = _tag(body, 'status_code');
      if (status != null && status != '200') {
        _log.i('No active challenge (status $status)');
        return null;
      }

      final words = _allTags(body, 'word');
      if (words.isEmpty) return null;

      return WatchwordChallenge(
        challengeId: _tag(body, 'challengeid') ?? '',
        words: words,
        wordCount: int.tryParse(_tag(body, 'wordcount') ?? '') ?? 4,
        round: int.tryParse(_tag(body, 'round') ?? '') ?? 1,
        maxRounds: int.tryParse(_tag(body, 'maxrounds') ?? '') ?? 3,
        remainingSeconds: int.tryParse(_tag(body, 'remaining') ?? '') ?? 0,
        locked: (_tag(body, 'locked') ?? '0') == '1',
      );
    } catch (e) {
      _log.w('Challenge fetch error: $e');
      return null;
    }
  }

  /// Builds the proof the server checks.
  ///
  /// Must mirror the server exactly — it hashes
  /// `one_time_pin + salt + otp_passphrase`, where salt is the hex string sent
  /// on the pairing URL and the passphrase is the ordered words joined by '-'.
  static String buildProof({
    required String challengeId,
    required String saltHex,
    required List<String> orderedWords,
  }) {
    final passphrase = orderedWords.join('-');
    final digest = sha256.convert(utf8.encode('$challengeId$saltHex$passphrase'));
    return digest.toString().toUpperCase();
  }

  void dispose() => _client.close(force: true);

  // The server speaks property_tree XML; these are enough for its flat shape.
  static String? _tag(String xml, String name) {
    final match = RegExp('<$name>(.*?)</$name>', dotAll: true).firstMatch(xml);
    if (match != null) return match.group(1)?.trim();
    final attr = RegExp('$name="([^"]*)"').firstMatch(xml);
    return attr?.group(1);
  }

  static List<String> _allTags(String xml, String name) {
    return RegExp('<$name>(.*?)</$name>', dotAll: true)
        .allMatches(xml)
        .map((m) => m.group(1)?.trim() ?? '')
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
  }
}
