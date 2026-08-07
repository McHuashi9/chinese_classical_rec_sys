import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/engine/app_logger.dart';
import 'package:chinese_classical_rec_sys/engine/db_version.dart';

class RemoteDbSync {
  static const _syncInterval = Duration(hours: 24);

  final SharedPreferences _prefs;
  final String _dbDirPath;
  final http.Client _client;

  static const _tmpName = 'classical.db.tmp';

  RemoteDbSync(this._prefs, this._dbDirPath, {http.Client? client})
      : _client = client ?? http.Client();

  /// 数据卷同步（下载阶段）。返回待替换的 tmp 文件路径，无需同步时返回 null。
  ///
  /// 版本决策：仅当远端版本比本地**新**才下载（方向判断，绝不降级）；
  /// 下载成功后暂不落主库，由调用方在 `db_replace` 成功后再 `markSynced()`。
  Future<String?> trySyncFromRelease({
    required String remoteVersion,
    required String downloadUrl,
  }) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final lastSync = _prefs.getInt('db_last_sync_ms') ?? 0;
      final since = now - lastSync;
      // 时钟回拨（负差）不阻塞检查，视为过期
      if (since >= 0 && since < _syncInterval.inMilliseconds) {
        AppLogger().debug('DB 同步跳过: 距上次同步不足 24h');
        return null;
      }

      final localVer = await _readLocalVersion();
      if (!isDbNewer(remoteVersion, localVer)) {
        AppLogger().info('DB 同步跳过: 远端 $remoteVersion 不新于本地 $localVer');
        return null;
      }

      final resp = await _client.get(Uri.parse(downloadUrl))
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        AppLogger().error('DB 同步失败: 下载 HTTP ${resp.statusCode}');
        return null;
      }

      final bytes = resp.bodyBytes;
      final body = _isGzip(bytes) ? _gunzip(bytes) : bytes;

      final tmp = File('$_dbDirPath/$_tmpName');
      await tmp.writeAsBytes(body);
      AppLogger().info('DB 已下载: $localVer → $remoteVersion（待替换）');
      return tmp.path;
    } catch (e) {
      AppLogger().error('同步失败: $e');
      return null;
    }
  }

  /// 替换成功后调用：写入"最近一次成功同步"标记（24h 冷却用）。
  Future<void> markSynced() async {
    await _prefs.setInt('db_last_sync_ms', DateTime.now().millisecondsSinceEpoch);
  }

  /// 同步成功后才调用：冷却"数据卷检查"（失败不冷却，下次启动可重试）。
  Future<void> markChecked() async {
    await _prefs.setInt('db_check_last_ms', DateTime.now().millisecondsSinceEpoch);
  }

  /// 替换成功后调用：把远端版本号写回 db_version.txt，
  /// 供下次启动的 asset 替换与后续同步做方向判断。
  Future<void> commitVersion(String version) async {
    final f = File('$_dbDirPath/db_version.txt');
    await f.writeAsString(version);
    AppLogger().info('DB 版本已写入: $version');
  }

  Future<String> _readLocalVersion() async {
    try {
      final f = File('$_dbDirPath/db_version.txt');
      if (!await f.exists()) return 'unknown';
      return (await f.readAsString()).trim();
    } catch (_) {
      return 'unknown';
    }
  }

  static bool _isGzip(List<int> bytes) {
    return bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
  }

  static List<int> _gunzip(List<int> bytes) => gzip.decode(bytes);
}