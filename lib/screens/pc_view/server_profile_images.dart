import 'dart:io' as io;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-server profile images, shared by the grid and focus-mode surfaces.
///
/// Both screens had their own copy of this. The copies drifted: focus mode
/// learned to copy the picked file into persistent storage — desktop pickers
/// hand back a temporary, security-scoped path that stops resolving once the
/// dialog closes — and the grid never did, so an image chosen there silently
/// disappeared on Windows and macOS.
class ServerProfileImages {
  const ServerProfileImages._();

  /// Prefix kept for backwards compatibility: renaming it would orphan every
  /// image users have already chosen.
  static const _prefPrefix = 'computer_bg_';

  static String prefKey(String uuid) => '$_prefPrefix$uuid';

  /// Every stored image, keyed by server uuid.
  static Future<Map<String, String>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, String>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefPrefix)) continue;
      final value = prefs.getString(key);
      if (value == null || value.isEmpty) continue;
      result[key.substring(_prefPrefix.length)] = value;
    }
    return result;
  }

  /// Opens the platform picker and stores the result.
  ///
  /// Returns the persisted path, or null if the user cancelled.
  static Future<String?> pick(String uuid) async {
    final pickedPath = await _showPicker();
    if (pickedPath == null || pickedPath.isEmpty) return null;

    final savedPath = await _persistLocally(pickedPath, uuid);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey(uuid), savedPath);
    return savedPath;
  }

  static Future<void> remove(String uuid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefKey(uuid));
  }

  static Future<String?> _showPicker() async {
    if (io.Platform.isMacOS) {
      const imageGroup = XTypeGroup(
        label: 'Images',
        extensions: ['jpg', 'jpeg', 'png', 'webp'],
      );
      final result = await openFile(acceptedTypeGroups: [imageGroup]);
      return result?.path;
    }
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    return picked?.path;
  }

  /// Copies the pick into the app's documents directory on desktop, where the
  /// picker's own path is temporary. Falls back to the original path if the
  /// copy fails — a possibly-working path beats none.
  static Future<String> _persistLocally(String pickedPath, String uuid) async {
    if (!io.Platform.isMacOS && !io.Platform.isWindows) return pickedPath;

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final bgDir = io.Directory(p.join(docsDir.path, 'backgrounds'));
      if (!bgDir.existsSync()) bgDir.createSync(recursive: true);

      final ext = p.extension(pickedPath).isNotEmpty
          ? p.extension(pickedPath)
          : '.jpg';
      final destFile = io.File(p.join(bgDir.path, '$uuid$ext'));
      await io.File(pickedPath).copy(destFile.path);
      return destFile.path;
    } catch (e) {
      debugPrint('ServerProfileImages: could not persist the pick: $e');
      return pickedPath;
    }
  }
}
