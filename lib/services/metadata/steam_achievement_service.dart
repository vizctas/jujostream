import 'dart:convert';
import 'package:http/http.dart' as http;

class AchievementProgress {
  final int total;
  final int unlocked;

  const AchievementProgress({required this.total, required this.unlocked});

  double get percent => total > 0 ? unlocked / total : 0.0;

  bool get isComplete => total > 0 && unlocked >= total;

  bool get inProgress => unlocked > 0 && unlocked < total;

  bool get neverStarted => total > 0 && unlocked == 0;
}

class SteamAchievementService {
  static const _base = 'https://api.steampowered.com';

  const SteamAchievementService();

  Future<AchievementProgress?> fetchGameProgress({
    required String apiKey,
    required String steamId,
    required int steamAppId,
  }) async {
    if (apiKey.isEmpty || steamId.isEmpty) return null;
    try {
      final uri = Uri.parse(
        '$_base/ISteamUserStats/GetPlayerAchievements/v1/',
      ).replace(queryParameters: {
        'key': apiKey,
        'steamid': steamId,
        'appid': '$steamAppId',
        'l': 'english',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final root = jsonDecode(response.body) as Map<String, dynamic>;
      final playerstats = root['playerstats'] as Map<String, dynamic>?;
      if (playerstats == null || playerstats['success'] != true) return null;
      final achievements = (playerstats['achievements'] as List?) ?? const [];
      final total = achievements.length;
      if (total == 0) return null;
      int unlocked = 0;
      for (final a in achievements) {
        if ((a as Map<String, dynamic>)['achieved'] == 1) unlocked++;
      }
      return AchievementProgress(total: total, unlocked: unlocked);
    } catch (_) {
      return null;
    }
  }
}
