import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../../models/nv_app.dart';

class MetadataDatabase {
  MetadataDatabase._();

  static const _kDbName = 'jujo_metadata.db';
  static const _kVersion = 2;
  static const _kTable = 'game_metadata';

  static Database? _db;

  static Future<Database> _open() async {
    _db ??= await openDatabase(
      join(await getDatabasesPath(), _kDbName),
      version: _kVersion,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE $_kTable (
          app_id        INTEGER PRIMARY KEY,
          game_name     TEXT NOT NULL,
          description   TEXT,
          genres        TEXT,
          metadata_genres TEXT,
          steam_video_url  TEXT,
          steam_video_thumb TEXT,
          rawg_clip_url TEXT,
          updated_at    INTEGER NOT NULL
        )
      '''),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_kTable ADD COLUMN metadata_genres TEXT',
          );
        }
        try {
          await db.execute(
            'ALTER TABLE $_kTable ADD COLUMN rawg_clip_url TEXT',
          );
        } catch (_) {}
      },
    );
    return _db!;
  }

  static Future<List<NvApp>> mergeInto(List<NvApp> apps) async {
    if (apps.isEmpty) return apps;
    try {
      final db = await _open();
      final rows = await db.query(_kTable);
      if (rows.isEmpty) return apps;

      return compute(_mergeRows, _MergePayload(apps, rows));
    } catch (_) {
      return apps;
    }
  }

  static List<NvApp> _mergeRows(_MergePayload payload) {
    final byId = <int, Map<String, Object?>>{
      for (final row in payload.rows) row['app_id'] as int: row,
    };

    return payload.apps.map((app) {
      final row = byId[app.appId];
      if (row == null) return app;

      final genresValue = (row['metadata_genres'] as String?) ??
          (row['genres'] as String?);
      final genres = genresValue?.split(',')
          .where((s) => s.isNotEmpty)
          .toList();

      return app.copyWith(
        description: (row['description'] as String?)?.isEmpty ?? true
            ? null
            : row['description'] as String?,
        metadataGenres: genres ?? const [],
        steamVideoUrl: row['steam_video_url'] as String?,
        steamVideoThumb: row['steam_video_thumb'] as String?,
        rawgClipUrl: row['rawg_clip_url'] as String?,
      );
    }).toList(growable: false);
  }

  static Future<void> saveAll(List<NvApp> apps) async {
    final enriched = apps.where((a) =>
        (a.description?.isNotEmpty ?? false) ||
        a.metadataGenres.isNotEmpty ||
        (a.steamVideoUrl?.isNotEmpty ?? false)).toList();
    if (enriched.isEmpty) return;
    try {
      final db = await _open();
      final batch = db.batch();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final app in enriched) {
        batch.insert(
          _kTable,
          {
            'app_id': app.appId,
            'game_name': app.appName,
            'description': app.description,
            'genres': app.metadataGenres.join(','),
            'metadata_genres': app.metadataGenres.join(','),
            'steam_video_url': app.steamVideoUrl,
            'steam_video_thumb': app.steamVideoThumb,
            'rawg_clip_url': app.rawgClipUrl,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (_) {

    }
  }

  static Future<void> pruneStale(List<NvApp> apps) async {
    if (apps.isEmpty) return;
    try {
      final db = await _open();
      final activeIds = apps.map((a) => a.appId).toList();
      await db.delete(
        _kTable,
        where:
            'app_id NOT IN (${activeIds.map((_) => '?').join(',')})',
        whereArgs: activeIds,
      );
    } catch (_) {}
  }
}

class _MergePayload {
  final List<NvApp> apps;
  final List<Map<String, Object?>> rows;
  const _MergePayload(this.apps, this.rows);
}
