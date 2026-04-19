import 'dart:convert';
import 'package:http/http.dart' as http;

class SteamAccountInfo {
  final String steamId;
  final String? personaName;
  final String? avatarUrl;

  const SteamAccountInfo({
    required this.steamId,
    this.personaName,
    this.avatarUrl,
  });
}

class SteamConnectService {
  static const _base = 'https://api.steampowered.com';

  Future<SteamAccountInfo?> validateConnection({
    required String apiKey,
    required String steamId,
  }) async {
    if (apiKey.isEmpty || steamId.isEmpty) return null;
    try {
      final uri = Uri.parse('$_base/ISteamUser/GetPlayerSummaries/v0002/')
          .replace(queryParameters: {
        'key': apiKey,
        'steamids': steamId,
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final root = jsonDecode(response.body) as Map<String, dynamic>;
      final players = (root['response'] as Map<String, dynamic>?)?['players'] as List?;
      if (players == null || players.isEmpty) return null;
      final first = players.first as Map<String, dynamic>;
      return SteamAccountInfo(
        steamId: first['steamid'] as String? ?? steamId,
        personaName: first['personaname'] as String?,
        avatarUrl: first['avatarfull'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<SteamAccountInfo?> fetchPublicProfile(String steamId) async {
    if (steamId.isEmpty) return null;
    try {
      final uri = Uri.parse(
          'https://steamcommunity.com/profiles/$steamId?xml=1');
      final response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (compatible)',
      }).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final body = response.body;

      final nameMatch = RegExp(
        r'<steamID><!\[CDATA\[([^\]]+)\]\]><\/steamID>',
        caseSensitive: false,
      ).firstMatch(body);

      final avatarMatch = RegExp(
        r'<avatarFull><!\[CDATA\[([^\]]+)\]\]><\/avatarFull>',
        caseSensitive: false,
      ).firstMatch(body);

      final name = nameMatch?.group(1)?.trim();
      final avatar = avatarMatch?.group(1)?.trim();

      if (name == null) return SteamAccountInfo(steamId: steamId);
      return SteamAccountInfo(
        steamId: steamId,
        personaName: name,
        avatarUrl: avatar,
      );
    } catch (_) {
      return null;
    }
  }
}
