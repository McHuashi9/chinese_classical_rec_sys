import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/engine/app_logger.dart';

class RemoteDbSync {
  static const _syncInterval = Duration(hours: 24);

  final SharedPreferences _prefs;
  final String _dbDirPath;
  final http.Client _client;

  RemoteDbSync(this._prefs, this._dbDirPath, {http.Client? client})
      : _client = client ?? http.Client();

  Future<bool> trySyncFromRelease({
    required String remoteVersion,
    required String downloadUrl,
  }) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final lastSync = _prefs.getInt('db_last_sync_ms') ?? 0;
      if (now - lastSync < _syncInterval.inMilliseconds) {
        AppLogger().debug('DB 同步跳过: 距上次同步不足 24h');
        return false;
      }

      final verPath = '$_dbDirPath/db_version.txt';
      String localVer = '';
      try {
        localVer = (await File(verPath).readAsString()).trim();
      } catch (_) {}

      if (remoteVersion == localVer) {
        AppLogger().debug('DB 同步跳过: 版本相同 ($remoteVersion)');
        return false;
      }

      final resp = await _client.get(Uri.parse(downloadUrl))
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        AppLogger().error('DB 同步失败: 下载 HTTP ${resp.statusCode}');
        return false;
      }

      final dbPath = '$_dbDirPath/classical.db';
      final tmp = File('$_dbDirPath/classical.db.tmp');
      final bak = File('$_dbDirPath/classical.db.bak');

      final bytes = resp.bodyBytes;
      final body = _isGzip(bytes) ? _gunzip(bytes) : bytes;

      await tmp.writeAsBytes(body);

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

  static bool _isGzip(List<int> bytes) {
    return bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
  }

  static List<int> _gunzip(List<int> bytes) => gzip.decode(bytes);
}
