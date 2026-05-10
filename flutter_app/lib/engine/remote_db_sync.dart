import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/engine/app_logger.dart';

class RemoteDbSync {
  static const _syncInterval = Duration(hours: 24);

  final SharedPreferences _prefs;
  final String _dbDirPath;

  RemoteDbSync(this._prefs, this._dbDirPath);

  Future<bool> trySyncFromRelease({
    required String remoteVersion,
    required String downloadUrl,
  }) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final lastSync = _prefs.getInt('db_last_sync_ms') ?? 0;
      if (now - lastSync < _syncInterval.inMilliseconds) return false;

      final verPath = '$_dbDirPath/db_version.txt';
      String localVer = '';
      try {
        localVer = (await File(verPath).readAsString()).trim();
      } catch (_) {}

      if (remoteVersion == localVer) return false;

      final resp = await http.get(Uri.parse(downloadUrl))
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return false;

      final dbPath = '$_dbDirPath/classical.db';
      final tmp = File('$_dbDirPath/classical.db.tmp');
      final bak = File('$_dbDirPath/classical.db.bak');

      await tmp.writeAsBytes(resp.bodyBytes);

      if (await bak.exists()) await bak.delete();
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await dbFile.rename(bak.path);
      }
      await tmp.rename(dbPath);
      await File(verPath).writeAsString(remoteVersion);
      await _prefs.setInt('db_last_sync_ms', now);
      AppLogger().info('DB 已同步: $localVer → $remoteVersion');
      return true;
    } catch (e) {
      AppLogger().error('同步失败: $e');
      return false;
    }
  }
}
