import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../../models/game_collection.dart';

class CollectionsService {
  CollectionsService._();

  static const _kDbName = 'jujo_collections.db';
  static const _kVersion = 1;
  static const _tCollections = 'collections';
  static const _tApps = 'collection_apps';

  static Database? _db;

  static Future<Database> _open() async {
    _db ??= await openDatabase(
      join(await getDatabasesPath(), _kDbName),
      version: _kVersion,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_tCollections (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            name       TEXT NOT NULL,
            color      INTEGER NOT NULL DEFAULT 0xFF533483,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE $_tApps (
            collection_id INTEGER NOT NULL REFERENCES $_tCollections(id) ON DELETE CASCADE,
            app_id        INTEGER NOT NULL,
            PRIMARY KEY (collection_id, app_id)
          )
        ''');
      },
    );
    return _db!;
  }

  static Future<int> create(String name, {int colorValue = 0xFF533483}) async {
    try {
      final db = await _open();
      return await db.insert(_tCollections, {
        'name': name,
        'color': colorValue,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('CollectionsService.create error: $e');
      return -1;
    }
  }

  static Future<void> rename(int id, String newName) async {
    try {
      final db = await _open();
      await db.update(
        _tCollections,
        {'name': newName},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('CollectionsService.rename error: $e');
    }
  }

  static Future<void> delete(int id) async {
    try {
      final db = await _open();
      await db.delete(_tApps, where: 'collection_id = ?', whereArgs: [id]);
      await db.delete(_tCollections, where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('CollectionsService.delete error: $e');
    }
  }

  static Future<void> addApp(int collectionId, int appId) async {
    try {
      final db = await _open();
      await db.insert(
        _tApps,
        {'collection_id': collectionId, 'app_id': appId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (e) {
      debugPrint('CollectionsService.addApp error: $e');
    }
  }

  static Future<void> removeApp(int collectionId, int appId) async {
    try {
      final db = await _open();
      await db.delete(
        _tApps,
        where: 'collection_id = ? AND app_id = ?',
        whereArgs: [collectionId, appId],
      );
    } catch (e) {
      debugPrint('CollectionsService.removeApp error: $e');
    }
  }

  static Future<List<GameCollection>> getAll() async {
    try {
      final db = await _open();
      final cols = await db.query(_tCollections, orderBy: 'created_at DESC');
      if (cols.isEmpty) return const [];

      final appsRows = await db.query(_tApps);
      final appsByCol = <int, Set<int>>{};
      for (final row in appsRows) {
        final cid = row['collection_id'] as int;
        final aid = row['app_id'] as int;
        appsByCol.putIfAbsent(cid, () => {}).add(aid);
      }

      return cols.map((c) {
        final id = c['id'] as int;
        return GameCollection(
          id: id,
          name: c['name'] as String,
          colorValue: c['color'] as int? ?? 0xFF533483,
          appIds: appsByCol[id] ?? {},
        );
      }).toList(growable: false);
    } catch (e) {
      debugPrint('CollectionsService.getAll error: $e');
      return const [];
    }
  }

  static Future<List<int>> collectionsForApp(int appId) async {
    try {
      final db = await _open();
      final rows = await db.query(
        _tApps,
        columns: ['collection_id'],
        where: 'app_id = ?',
        whereArgs: [appId],
      );
      return rows.map((r) => r['collection_id'] as int).toList();
    } catch (e) {
      return const [];
    }
  }
}
