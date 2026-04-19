import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class SessionHistoryService {
  SessionHistoryService._();

  static const _kDbName = 'jujo_sessions.db';
  static const _kVersion = 1;
  static const _kTable = 'sessions';

  static Database? _db;

  static Future<Database> _open() async {
    _db ??= await openDatabase(
      join(await getDatabasesPath(), _kDbName),
      version: _kVersion,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE $_kTable (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          app_id        INTEGER NOT NULL,
          app_name      TEXT NOT NULL,
          server_id     TEXT NOT NULL,
          server_name   TEXT NOT NULL,
          start_time_ms INTEGER NOT NULL,
          end_time_ms   INTEGER NOT NULL,
          duration_sec  INTEGER NOT NULL,
          avg_fps       REAL,
          avg_bitrate   INTEGER
        )
      '''),
    );
    return _db!;
  }

  static Future<void> insertSession({
    required int appId,
    required String appName,
    required String serverId,
    required String serverName,
    required DateTime startTime,
    required DateTime endTime,
    double? avgFps,
    int? avgBitrate,
  }) async {
    final duration = endTime.difference(startTime).inSeconds;
    if (duration < 5) return;
    try {
      final db = await _open();
      await db.insert(_kTable, {
        'app_id': appId,
        'app_name': appName,
        'server_id': serverId,
        'server_name': serverName,
        'start_time_ms': startTime.millisecondsSinceEpoch,
        'end_time_ms': endTime.millisecondsSinceEpoch,
        'duration_sec': duration,
        'avg_fps': avgFps,
        'avg_bitrate': avgBitrate,
      });
    } catch (e) {
      debugPrint('SessionHistoryService.insertSession error: $e');
    }
  }

  static Future<int> totalPlaytimeSec(int appId) async {
    try {
      final db = await _open();
      final result = await db.rawQuery(
        'SELECT SUM(duration_sec) as total FROM $_kTable WHERE app_id = ?',
        [appId],
      );
      return (result.first['total'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> totalPlaytimeAllSec() async {
    try {
      final db = await _open();
      final result = await db.rawQuery(
        'SELECT SUM(duration_sec) as total FROM $_kTable',
      );
      return (result.first['total'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> distinctGamesCount() async {
    try {
      final db = await _open();
      final result = await db.rawQuery(
        'SELECT COUNT(DISTINCT app_id) as cnt FROM $_kTable',
      );
      return (result.first['cnt'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<List<Map<String, Object?>>> recentSessions({int limit = 20}) async {
    try {
      final db = await _open();
      return db.query(
        _kTable,
        orderBy: 'start_time_ms DESC',
        limit: limit,
      );
    } catch (_) {
      return const [];
    }
  }

  static Future<List<int>> topPlayedAppIds({int limit = 20}) async {
    try {
      final db = await _open();
      final rows = await db.rawQuery(
        'SELECT app_id, SUM(duration_sec) as total '
        'FROM $_kTable '
        'GROUP BY app_id '
        'ORDER BY total DESC '
        'LIMIT ?',
        [limit],
      );
      return rows.map((r) => (r['app_id'] as int)).toList();
    } catch (_) {
      return const [];
    }
  }

  static String formatDuration(int totalSec) {
    if (totalSec < 60) return '< 1m';
    final hours = totalSec ~/ 3600;
    final minutes = (totalSec % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}
