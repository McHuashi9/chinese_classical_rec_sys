import 'dart:io' show Directory, File;
import 'dart:typed_data';

import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/engine/app_logger.dart';
import 'package:chinese_classical_rec_sys/engine/db_version.dart';

/// 应用支持目录提供器；生产由 path_provider 提供，测试可注入临时目录。
typedef SupportDirectoryProvider = Future<Directory> Function();

/// 资产字节读取器；生产由 rootBundle 提供，测试可注入内存 fixture。
typedef AssetBytesLoader = Future<Uint8List> Function(String assetPath);

/// 资产文本读取器；生产由 rootBundle 提供，测试可注入内存 fixture。
typedef AssetStringLoader = Future<String> Function(String assetPath);

/// `db_replace` 的 Dart 调用入口；生产为 `NativeBridge.dbReplaceUtf8`。
typedef DbReplaceCallback = int Function(String newPath, String currentPath);

/// 启动阶段内容库路径解析结果。
class DbPathResolution {
  const DbPathResolution({
    required this.contentPath,
    required this.userPath,
    required this.replaced,
  });

  final String contentPath;
  final String userPath;

  /// 本次启动是否实际执行了内置内容库替换。
  final bool replaced;
}

/// 解析/准备启动所需的内容库与用户库路径。
///
/// 负责首装资产复制、`.bak` 恢复、遗留 `.tmp` 清理、内置资产升级方向判断
/// 与替换失败回退。所有外部依赖可从构造参数注入，行为由
/// `test/engine/db_path_resolver_test.dart` 直接覆盖。
class DbPathResolver {
  DbPathResolver({
    required this.supportDirectoryProvider,
    required this.assetBytesLoader,
    required this.assetStringLoader,
    required this.dbReplace,
    AppLogger Function()? logger,
  }) : _logger = logger ?? AppLogger.new;

  static const contentAssetPath = 'assets/data/classical.db';
  static const versionAssetPath = 'assets/data/db_version.txt';

  final SupportDirectoryProvider supportDirectoryProvider;
  final AssetBytesLoader assetBytesLoader;
  final AssetStringLoader assetStringLoader;
  final DbReplaceCallback dbReplace;
  final AppLogger Function() _logger;

  Future<DbPathResolution> resolve() async {
    var replaced = false;
    try {
      final dir = await supportDirectoryProvider();
      final dbPath = '${dir.path}/classical.db';
      final userPath = '${dir.path}/user.db';
      final verPath = '${dir.path}/db_version.txt';
      final dbFile = File(dbPath);
      final bakFile = File('${dir.path}/classical.db.bak');

      // 用户库不复制 asset、不删除；由 C++ db_open 首次自动创建。
      // 仅确保父目录存在（getApplicationSupportDirectory 通常已存在）。
      try {
        if (!await File(userPath).parent.exists()) {
          await File(userPath).parent.create(recursive: true);
        }
      } catch (_) {}

      // 清理上次会话中断残留的同步中间文件（L4）
      try {
        final staleTmp = File('${dir.path}/classical.db.tmp');
        if (await staleTmp.exists()) await staleTmp.delete();
      } catch (_) {}

      if (!await dbFile.exists() && await bakFile.exists()) {
        await bakFile.rename(dbPath);
        // .bak 对应的版本无法确定：标记 unknown 交由方向判断自愈（宁可用资产升级，
        // 也不让“旧内容挂着新版本号”阻塞后续同步）
        try {
          await File(verPath).writeAsString('unknown');
        } catch (_) {}
        _logger().info('DB 已从 .bak 恢复，版本标记 unknown');
      }

      if (!await dbFile.exists()) {
        final data = await assetBytesLoader(contentAssetPath);
        await dbFile.writeAsBytes(data);
        final assetVer = await _readAssetDbVersion();
        await File(verPath).writeAsString(assetVer);
        _logger().info('DB 首次安装: $assetVer');
      } else {
        final assetVer = await _readAssetDbVersion();
        String localVer;
        try {
          localVer = (await File(verPath).readAsString()).trim();
        } catch (_) {
          localVer = 'unknown';
        }
        // 方向判断：仅当内置数据比本地新才替换（D1 修复）
        if (isDbNewer(assetVer, localVer)) {
          final tmp = File('${dir.path}/classical.db.tmp');
          final data = await assetBytesLoader(contentAssetPath);
          await tmp.writeAsBytes(data);
          final rc = dbReplace(tmp.path, dbPath);
          if (rc == BridgeError.ok) {
            await File(verPath).writeAsString(assetVer);
            replaced = true;
            _logger().info('DB 已升级: $localVer → $assetVer（用户数据已保留）');
          } else {
            if (await tmp.exists()) await tmp.delete();
            _logger().error('内置数据升级失败 rc=$rc，已保留旧库');
          }
        } else {
          _logger().info('DB 检查: 内置数据 $assetVer 不新于本地 $localVer，跳过替换');
          // 上次替换留下的 .bak 已无用途（本地库保持最新），顺手清理（N21）
          try {
            if (await bakFile.exists()) await bakFile.delete();
          } catch (_) {}
        }
      }
      return DbPathResolution(
        contentPath: dbPath,
        userPath: userPath,
        replaced: replaced,
      );
    } catch (e) {
      _logger().warn('DB 路径解析失败: $e，回退到相对路径');
      return const DbPathResolution(
        contentPath: '../data/classical.db',
        userPath: '../data/user.db',
        replaced: false,
      );
    }
  }

  Future<String> _readAssetDbVersion() async {
    try {
      final data = await assetStringLoader(versionAssetPath);
      return data.trim();
    } catch (_) {
      return 'unknown';
    }
  }
}
