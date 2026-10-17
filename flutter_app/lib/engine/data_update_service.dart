import 'dart:convert';
import 'dart:io' show File;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chinese_classical_rec_sys/engine/app_logger.dart';
import 'package:chinese_classical_rec_sys/engine/db_version.dart';
import 'package:chinese_classical_rec_sys/engine/github_config.dart';

/// 当前数据卷更新检查的冷却 key。
const String kDbCheckLastMsKey = 'db_check_last_ms';

/// 从 release 资产中选出的待下载数据卷。
class RemoteDataAsset {
  const RemoteDataAsset({required this.version, required this.downloadUrl});

  final String version;
  final String downloadUrl;
}

/// 执行实际下载/替换的回调；生产由 `AppCoordinator.remoteSyncDb` 提供。
typedef RemoteDataSyncRunner = Future<void> Function(
    String remoteVersion, String downloadUrl);

/// 数据卷静默更新检查。
///
/// 职责只包含：启动冷却判定、查询 GitHub release、选择 `classical.db.gz` +
/// `db_version.txt`、比较本地版本并触发注入的远程同步回调。真正的下载/替换与
/// 用户库保留仍由 `AppCoordinator.remoteSyncDb` / `RemoteDbSync` 负责。
class DataUpdateService {
  DataUpdateService({
    required this.prefs,
    required this.dbDirPath,
    required this.syncRunner,
    http.Client? client,
    DateTime Function()? now,
    Future<String> Function()? localVersionReader,
    this.checkInterval = const Duration(hours: 24),
    this.requestTimeout = const Duration(seconds: 30),
    AppLogger Function()? logger,
  })  : _client = client,
        _now = now ?? DateTime.now,
        _localVersionReader = localVersionReader,
        _logger = logger ?? AppLogger.new;

  final SharedPreferences prefs;
  final String dbDirPath;
  final RemoteDataSyncRunner syncRunner;
  final http.Client? _client;
  final DateTime Function() _now;
  final Future<String> Function()? _localVersionReader;
  final Duration checkInterval;
  final Duration requestTimeout;
  final AppLogger Function() _logger;

  /// 读取本地数据卷版本；文件缺失或读取失败返回 `unknown`。
  Future<String> readLocalDbVersion() async {
    try {
      final reader = _localVersionReader;
      if (reader != null) return (await reader()).trim();
      final f = File('$dbDirPath/db_version.txt');
      if (!await f.exists()) return 'unknown';
      return (await f.readAsString()).trim();
    } catch (_) {
      return 'unknown';
    }
  }

  /// 检查是否发现可用的新数据卷；返回 null 表示跳过/失败/无更新。
  Future<RemoteDataAsset?> fetchLatestAsset() async {
    final now = _now().millisecondsSinceEpoch;
    final lastCheck = prefs.getInt(kDbCheckLastMsKey) ?? 0;
    final since = now - lastCheck;
    // 时钟回拨（负差）不阻塞检查；只有“真正成功检查/同步”才写冷却标记
    if (since >= 0 && since < checkInterval.inMilliseconds) {
      _logger().debug('DB 检查跳过: 距上次检查不足 ${checkInterval.inHours}h');
      return null;
    }

    final resp = await _get(
      Uri.parse(GithubConfig.releaseApiList),
      headers: const {'Accept': 'application/vnd.github.v3+json'},
    ).timeout(requestTimeout);
    if (resp.statusCode != 200) {
      _logger().warn('DB 检查失败: release 列表 HTTP ${resp.statusCode}');
      return null;
    }

    final releases = jsonDecode(resp.body) as List<dynamic>;
    // 是否至少完整评估过一个含资产的 release（版本文件下载成功 + 方向判断完成）
    var evaluatedAnyAsset = false;
    for (final r in releases) {
      final release = r as Map<String, dynamic>;
      final assets = release['assets'] as List<dynamic>?;
      if (assets == null) continue;

      String? dbUrl;
      String? verUrl;
      for (final a in assets) {
        final map = a as Map<String, dynamic>;
        final name = map['name'] as String?;
        final url = map['browser_download_url'] as String?;
        if (name == 'classical.db.gz') dbUrl = url;
        if (name == 'db_version.txt') verUrl = url;
      }
      if (dbUrl == null || verUrl == null) continue;

      final verResp = await _get(Uri.parse(verUrl)).timeout(requestTimeout);
      if (verResp.statusCode != 200) {
        _logger().warn('DB 检查: db_version.txt 下载失败 HTTP ${verResp.statusCode}');
        continue;
      }
      evaluatedAnyAsset = true;
      final remoteVer = verResp.body.trim();

      final localVer = await readLocalDbVersion();
      if (!isDbNewer(remoteVer, localVer)) {
        _logger().info('DB 检查: 远端 $remoteVer 不新于本地 $localVer，跳过');
        // 已成功核实无更新：本次检查有效，写入冷却避免每次启动都请求 API
        await prefs.setInt(kDbCheckLastMsKey, now);
        return null;
      }

      _logger().info('DB 检查: 发现新数据卷 $remoteVer (本地 $localVer)');
      return RemoteDataAsset(version: remoteVer, downloadUrl: dbUrl);
    }
    _logger().info('DB 检查: 最近的 release 中未找到数据资产，跳过');
    // 仅当至少完整评估过一个含资产的 release 才写冷却：
    // 版本文件持续下载失败说明检查未真正成功，不冷却，下次启动可重试
    if (evaluatedAnyAsset) {
      await prefs.setInt(kDbCheckLastMsKey, now);
    }
    return null;
  }

  /// 运行静默更新；任何异常只记日志，绝不影响启动主流程。
  Future<void> runSilentSync() async {
    try {
      final asset = await fetchLatestAsset();
      if (asset == null) return;
      await syncRunner(asset.version, asset.downloadUrl);
    } catch (e, st) {
      _logger().error('silent remote DB sync failed: $e\n$st');
    }
  }

  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) {
    final client = _client;
    if (client != null) return client.get(uri, headers: headers);
    return http.get(uri, headers: headers);
  }
}
