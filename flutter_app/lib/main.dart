import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show File, Platform;
import 'dart:ui' show AppExitResponse, Color;
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator, rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'state/coordinator.dart';
import 'bridge/ffi_bindings.dart';
import 'bridge/c_types.dart';
import 'state/navigation_controller.dart';
import 'state/settings_controller.dart';
import 'state/reading_controller.dart';
import 'state/user_controller.dart';
import 'engine/read_tracker.dart';
import 'engine/github_config.dart';
import 'engine/db_version.dart';
import 'engine/app_logger.dart';
import 'engine/announcement.dart';
import 'theme/theme.dart';
import 'pages/read_hub_page.dart';
import 'pages/my_page.dart';
import 'pages/settings_page.dart';
import 'pages/init_onboarding_page.dart';
import 'widgets/dialogs.dart';
import 'widgets/announcement_dialog.dart';
import 'widgets/profile_dialogs.dart';

void main() {
  final readTracker = ReadTracker();
  final navCtrl = NavigationController();
  final settingsCtrl = SettingsController();
  final readingCtrl = ReadingController(readTracker);
  final userCtrl = UserController();
  final coordinator = AppCoordinator(
    navCtrl: navCtrl,
    settingsCtrl: settingsCtrl,
    readingCtrl: readingCtrl,
    userCtrl: userCtrl,
    readTracker: readTracker,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: navCtrl),
        ChangeNotifierProvider.value(value: settingsCtrl),
        ChangeNotifierProvider.value(value: readingCtrl),
        ChangeNotifierProvider.value(value: userCtrl),
        Provider.value(value: coordinator),
      ],
      child: const ChineseClassicalRecSysApp(),
    ),
  );
}

class ChineseClassicalRecSysApp extends StatelessWidget {
  const ChineseClassicalRecSysApp({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final screenSize = AppTheme.screenSizeForWidth(constraints.maxWidth);
      final isDark = context.select((SettingsController s) => s.darkMode);
      final fontScale = context.select((SettingsController s) => s.fontScale);
      final accent =
          Color(context.select((SettingsController s) => s.accentColorValue));

      return MaterialApp(
        title: '文言文推荐系统',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(screenSize, fontScale, accentColor: accent),
        darkTheme:
            AppTheme.darkTheme(screenSize, fontScale, accentColor: accent),
        themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        home: const MainShell(),
      );
    });
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with TickerProviderStateMixin {
  late final List<Widget> _pages;

  static const _dbSyncInterval = Duration(hours: 24);

  bool _initialized = false;
  String? _initError;
  int _pageIndex = 0;
  int _prevPageIndex = 0;
  bool _transitioning = false;
  bool _isReading = false;
  AppCoordinator? _coord;
  String _dbDirPath = '';

  late final AnimationController _ctrl;
  late Animation<Offset> _slideOut;
  late Animation<Offset> _slideIn;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _pages = <Widget>[
      const RepaintBoundary(child: ReadHubPage()), // 0 阅读
      const RepaintBoundary(child: MyPage()), // 1 我的
      const RepaintBoundary(child: SettingsPage()), // 2 设置
    ];
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _transitioning = false);
      }
    });

    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _onExitRequested,
      onPause: _onBackground,
      onHide: _onBackground,
      onResume: _onForeground,
      onShow: _onForeground,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _coord = context.read<AppCoordinator>();
      _coord!.initialized.addListener(_onInitChanged);
      _coord!.settingsCtrl.addListener(_onSettingsError);
      _coord!.readingCtrl.addListener(_onReadingChanged);
      _coord!.navCtrl.addListener(_onNavChanged);
      _initApp(_coord!);
    });
  }

  Future<void> _initApp(AppCoordinator coord) async {
    DynamicLibrary lib;
    try {
      lib = _loadLibrary();
    } catch (e) {
      AppLogger().error('FFI load failed: $e');
      if (!mounted) return;
      setState(() => _initError = '无法加载核心组件，请尝试重新安装。\n$e');
      return;
    }
    final (contentPath, userPath, replaced) =
        await _resolveDbPath(NativeBridge.fromLib(lib));
    bool initOk;
    try {
      initOk = await coord.init(contentPath, userPath, lib);
    } catch (e) {
      AppLogger().error('数据库初始化失败: $e');
      if (!mounted) return;
      setState(() => _initError = '无法加载核心组件，请尝试重新安装。\n$e');
      return;
    }
    if (!initOk) {
      if (!mounted) return;
      setState(() => _initError = _dbOpenErrorMessage(coord.dbOpenErrorCode));
      return;
    }
    if (!mounted) return;
    if (replaced) {
      coord.settingsCtrl.setNotice('内容已更新，学习进度已保留');
    }
    coord.setContentPathAfterSync(contentPath);

    final prefs = await SharedPreferences.getInstance();
    final dbDir = File(contentPath).parent.path;
    _dbDirPath = dbDir;
    coord.setContentDataVersion(await _readLocalDbVersion());
    coord.initRemoteDbSync(prefs, dbDir);
    // 在 activateSavedProfile 之前先判定，避免用 active_user_id 做“是否已引导”的标记。
    final shouldShowOnboarding =
        shouldShowProfileOnboarding(prefs, coord.userCtrl.profiles);
    coord.activateSavedProfile();
    coord.getRecommendations(10);
    await coord.settingsCtrl.init(prefs, coord.bridge);
    if (!mounted) return;
    await _maybeShowAnnouncement(coord, prefs);
    if (!mounted) return;
    if (shouldShowOnboarding) {
      await runProfileOnboarding(context, coord);
      await markProfileOnboardingSeen(prefs);
      if (!mounted) return;
    }
    if (!coord.userCtrl.isInitialized) {
      await _showInitGuide(coord);
    }
    if (!mounted) return;
    _postInit(coord);
  }

  String _dbOpenErrorMessage(int? code) {
    switch (code) {
      case BridgeError.errDbContent:
        return '内容库缺失或损坏，请重启应用。\n若持续出现，请重新安装。';
      case BridgeError.errDbUser:
        return '用户库缺失或损坏，请重启应用。\n若持续出现，请重新安装。';
      case BridgeError.errDbVersion:
        return '数据库版本不兼容，请更新应用或重新安装。';
      case BridgeError.errDbSamePath:
        return '内容库与用户库路径相同，请重启应用。';
      default:
        return '数据库打开失败，请重启应用。\n若持续出现，请重新安装。';
    }
  }

  Future<void> _maybeShowAnnouncement(
      AppCoordinator coord, SharedPreferences prefs) async {
    final seen = prefs.getString('announcement_seen_id');
    if (seen == kCurrentAnnouncement.id) return;
    if (!mounted) return;
    await AnnouncementDialog.show(context, announcement: kCurrentAnnouncement);
    await prefs.setString('announcement_seen_id', kCurrentAnnouncement.id);
  }

  Future<void> _showInitGuide(AppCoordinator coord) async {
    // 强制初始化不能跳过：反复弹引导，直到用户完成初始化。
    while (!coord.userCtrl.isInitialized && mounted) {
      if (!mounted) return;
      final start = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('初始化引导'),
            content: const Text(
              '新用户需要先完成 6 道带原文的初始化题，才能正常使用推荐与随堂练习。'
              '整个过程约 3 分钟，无法跳过。',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('开始初始化'),
              ),
            ],
          ),
        ),
      );
      if (start != true || !mounted) continue;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const InitOnboardingPage()),
      );
    }
  }

  void _postInit(AppCoordinator coord) {
    _silentCheckForUpdates(coord).catchError((e, st) {
      AppLogger().error('silent check for updates failed: $e\n$st');
    });
    _silentRemoteDbSync(coord).catchError((e, st) {
      AppLogger().error('silent remote DB sync failed: $e\n$st');
    });
  }

  Future<void> _silentCheckForUpdates(AppCoordinator coord) async {
    final latest = await coord.settingsCtrl
        .silentCheckForUpdates(AppCoordinator.currentVersion);
    if (latest != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('发现新版本 v$latest（当前 ${AppCoordinator.currentVersion}）'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: '查看',
            onPressed: () {
              coord.navCtrl.switchPage(2);
            },
          ),
        ),
      );
    }
  }

  Future<void> _silentRemoteDbSync(AppCoordinator coord) async {
    final asset = await _fetchLatestDataAsset();
    if (asset == null) return;
    await _syncIfNewer(coord, asset.$1, asset.$2);
  }

  Future<String> _readLocalDbVersion() async {
    try {
      final f = File('$_dbDirPath/db_version.txt');
      if (!await f.exists()) return 'unknown';
      return (await f.readAsString()).trim();
    } catch (_) {
      return 'unknown';
    }
  }

  Future<(String, String)?> _fetchLatestDataAsset() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastCheck = prefs.getInt('db_check_last_ms') ?? 0;
    final since = now - lastCheck;
    // 时钟回拨（负差）不阻塞检查；只有"真正成功检查/同步"才写冷却标记
    if (since >= 0 && since < _dbSyncInterval.inMilliseconds) {
      AppLogger().debug('DB 检查跳过: 距上次检查不足 24h');
      return null;
    }

    final resp =
        await http.get(Uri.parse(GithubConfig.releaseApiList), headers: {
      'Accept': 'application/vnd.github.v3+json',
    }).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      AppLogger().warn('DB 检查失败: release 列表 HTTP ${resp.statusCode}');
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

      final verResp = await http.get(Uri.parse(verUrl));
      if (verResp.statusCode != 200) {
        AppLogger()
            .warn('DB 检查: db_version.txt 下载失败 HTTP ${verResp.statusCode}');
        continue;
      }
      evaluatedAnyAsset = true;
      final remoteVer = verResp.body.trim();

      final localVer = await _readLocalDbVersion();
      if (!isDbNewer(remoteVer, localVer)) {
        AppLogger().info('DB 检查: 远端 $remoteVer 不新于本地 $localVer，跳过');
        // 已成功核实无更新：本次检查有效，写入冷却避免每次启动都请求 API
        await prefs.setInt('db_check_last_ms', now);
        return null;
      }

      AppLogger().info('DB 检查: 发现新数据卷 $remoteVer (本地 $localVer)');
      return (remoteVer, dbUrl);
    }
    AppLogger().info('DB 检查: 最近的 release 中未找到数据资产，跳过');
    // 仅当至少完整评估过一个含资产的 release 才写冷却：
    // 版本文件持续下载失败说明检查未真正成功，不冷却，下次启动可重试
    if (evaluatedAnyAsset) {
      await prefs.setInt('db_check_last_ms', now);
    }
    return null;
  }

  Future<void> _syncIfNewer(
      AppCoordinator coord, String version, String url) async {
    try {
      await coord.remoteSyncDb(remoteVersion: version, downloadUrl: url);
    } catch (_) {}
  }

  Future<(String, String, bool)> _resolveDbPath(NativeBridge bridge) async {
    var replaced = false;
    try {
      final dir = await getApplicationSupportDirectory();
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
        // 也不让"旧内容挂着新版本号"阻塞后续同步）
        try {
          await File(verPath).writeAsString('unknown');
        } catch (_) {}
        AppLogger().info('DB 已从 .bak 恢复，版本标记 unknown');
      }

      if (!await dbFile.exists()) {
        final data = await rootBundle.load('assets/data/classical.db');
        await dbFile.writeAsBytes(data.buffer.asUint8List());
        final assetVer = await _readAssetDbVersion();
        await File(verPath).writeAsString(assetVer);
        AppLogger().info('DB 首次安装: $assetVer');
      } else {
        final assetVer = await _readAssetDbVersion();
        String localVer = '';
        try {
          localVer = (await File(verPath).readAsString()).trim();
        } catch (_) {
          localVer = 'unknown';
        }
        // 方向判断：仅当内置数据比本地新才替换（D1 修复）
        if (isDbNewer(assetVer, localVer)) {
          final tmp = File('${dir.path}/classical.db.tmp');
          final data = await rootBundle.load('assets/data/classical.db');
          await tmp.writeAsBytes(data.buffer.asUint8List());
          final rc = _callDbReplace(bridge, tmp.path, dbPath);
          if (rc == BridgeError.ok) {
            await File(verPath).writeAsString(assetVer);
            replaced = true;
            AppLogger().info('DB 已升级: $localVer → $assetVer（用户数据已保留）');
          } else {
            if (await tmp.exists()) await tmp.delete();
            AppLogger().error('内置数据升级失败 rc=$rc，已保留旧库');
          }
        } else {
          AppLogger().info('DB 检查: 内置数据 $assetVer 不新于本地 $localVer，跳过替换');
          // 上次替换留下的 .bak 已无用途（本地库保持最新），顺手清理（N21）
          try {
            if (await bakFile.exists()) await bakFile.delete();
          } catch (_) {}
        }
      }
      return (dbPath, userPath, replaced);
    } catch (e) {
      AppLogger().warn('_resolveDbPath 失败: $e，回退到相对路径');
      return ('../data/classical.db', '../data/user.db', false);
    }
  }

  Future<String> _readAssetDbVersion() async {
    try {
      final data = await rootBundle.loadString('assets/data/db_version.txt');
      return data.trim();
    } catch (_) {
      return 'unknown';
    }
  }

  int _callDbReplace(NativeBridge bridge, String newPath, String curPath) {
    final np = newPath.toNativeUtf8(allocator: calloc);
    final cp = curPath.toNativeUtf8(allocator: calloc);
    final rc = bridge.dbReplace(np, cp);
    calloc.free(np);
    calloc.free(cp);
    return rc;
  }

  DynamicLibrary _loadLibrary() {
    if (Platform.isLinux) {
      final execDir = File(Platform.resolvedExecutable).parent;
      return DynamicLibrary.open('${execDir.path}/lib/libchinese_core.so');
    }
    if (Platform.isMacOS) {
      final execDir = File(Platform.resolvedExecutable).parent;
      return DynamicLibrary.open(
          '${execDir.path}/../Frameworks/libchinese_core.dylib');
    }
    if (Platform.isWindows) {
      final execDir = File(Platform.resolvedExecutable).parent;
      return DynamicLibrary.open('${execDir.path}/chinese_core.dll');
    }
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libchinese_core.so');
    }
    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }
    throw UnsupportedError(
      '文言文推荐系统 不支持当前平台。'
      '当前平台: ${Platform.operatingSystem}',
    );
  }

  void _onInitChanged() {
    if (_coord!.initialized.value && !_initialized) {
      setState(() => _initialized = true);
    }
  }

  void _onSettingsError() {
    final error = _coord!.settingsCtrl.error;
    if (error != null) {
      if (!mounted) return;
      _coord!.settingsCtrl.clearError();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final notice = _coord!.settingsCtrl.notice;
    if (notice != null) {
      if (!mounted) return;
      _coord!.settingsCtrl.clearNotice();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(notice),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onReadingChanged() {
    final isReading = _coord!.readingCtrl.isReading;
    if (_isReading != isReading) {
      _isReading = isReading;
      setState(() {});
    }
  }

  void _onNavChanged() {
    final pageIndex = _coord!.navCtrl.pageIndex;
    if (_pageIndex != pageIndex) {
      _prevPageIndex = _pageIndex;
      _pageIndex = pageIndex;
      _startTransition();
    }
  }

  void _startTransition() {
    final d = (_pageIndex > _prevPageIndex ? 1.0 : -1.0);
    _slideOut = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(-d * 0.08, 0),
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutQuart));
    _slideIn = Tween<Offset>(
      begin: Offset(d * 0.08, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutQuart));
    _transitioning = true;
    _ctrl.forward(from: 0.0);
  }

  void _onDestinationSelected(int index) {
    if (index == _pageIndex) return;
    final coord = _coord;
    if (coord != null && coord.readingCtrl.isReading && index != 0) {
      _showAbandonDialog(index);
      return;
    }
    _coord?.navCtrl.switchPage(index);
  }

  Future<void> _showAbandonDialog(int targetIndex) async {
    final coord = _coord!;
    coord.readingCtrl.pauseTimer();
    final discard = await showConfirmDialog(
      context,
      title: '放弃阅读？',
      content: '阅读中切换页面将放弃当前记录。确定吗？',
      confirmLabel: '放弃',
    );
    if (discard) {
      coord.readingCtrl.stopTimer();
      coord.applyReadingEffect();
      coord.readingCtrl.discardReading();
      coord.navCtrl.switchPage(targetIndex);
    } else {
      coord.readingCtrl.resumeTimer();
    }
  }

  void _onBackground() => _coord?.readingCtrl.pauseTimer();
  void _onForeground() => _coord?.readingCtrl.resumeTimer();

  Future<AppExitResponse> _onExitRequested() async {
    final coord = _coord;
    if (coord == null) return AppExitResponse.exit;

    coord.readingCtrl.stopTimer();
    coord.applyReadingEffect();

    if (!coord.readingCtrl.hasUnrecordedReading) return AppExitResponse.exit;

    final discard = await showConfirmDialog(context,
        title: '确认退出',
        content: '当前文章阅读未满30秒，未完成追踪。确定要放弃当前阅读记录并退出吗？',
        confirmLabel: '放弃并退出');
    if (!context.mounted) return AppExitResponse.exit;
    if (discard) {
      coord.readingCtrl.discardReading();
    } else {
      coord.readingCtrl.resumeTimer();
    }
    return discard ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  @override
  void dispose() {
    _coord?.initialized.removeListener(_onInitChanged);
    _coord?.settingsCtrl.removeListener(_onSettingsError);
    _coord?.readingCtrl.removeListener(_onReadingChanged);
    _coord?.navCtrl.removeListener(_onNavChanged);
    _ctrl.dispose();
    _lifecycleListener.dispose();
    super.dispose();
  }

  Future<void> _onBackPressed(bool didPop, _) async {
    if (didPop) return;
    final coord = _coord;
    if (coord == null || !coord.readingCtrl.isReading) {
      final exit = await showConfirmDialog(
        context,
        title: '确认退出',
        content: '确定要退出应用吗？',
        confirmLabel: '退出',
      );
      if (exit && context.mounted) SystemNavigator.pop();
      return;
    }

    coord.readingCtrl.stopTimer();
    coord.applyReadingEffect();

    if (!coord.readingCtrl.hasUnrecordedReading) {
      final exit = await showConfirmDialog(
        context,
        title: '确认退出',
        content: '确定要退出应用吗？',
        confirmLabel: '退出',
      );
      if (exit && context.mounted) {
        SystemNavigator.pop();
      } else {
        coord.readingCtrl.resumeTimer();
      }
      return;
    }

    final discard = await showConfirmDialog(
      context,
      title: '确认退出',
      content: '当前文章阅读未满30秒，未完成追踪。放弃并退出？',
      confirmLabel: '放弃并退出',
    );
    if (!context.mounted) return;
    if (discard) {
      coord.readingCtrl.discardReading();
      SystemNavigator.pop();
    } else {
      coord.readingCtrl.resumeTimer();
    }
  }

  final _bodyKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isNarrow = width < 600;
    final isFullLabel = width >= AppTheme.breakLarge;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onBackPressed,
      child: Scaffold(
        body: SafeArea(
          child: _isReading
              ? _buildBody()
              : isNarrow
                  ? _buildBody()
                  : Row(
                      children: [
                        NavigationRail(
                          selectedIndex: _pageIndex,
                          labelType: isFullLabel
                              ? NavigationRailLabelType.all
                              : NavigationRailLabelType.selected,
                          onDestinationSelected: _onDestinationSelected,
                          destinations: const [
                            NavigationRailDestination(
                              icon: Icon(Icons.menu_book),
                              label: Text('阅读'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.person),
                              label: Text('我的'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.settings),
                              label: Text('设置'),
                            ),
                          ],
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: _buildBody()),
                      ],
                    ),
        ),
        bottomNavigationBar: _isReading
            ? null
            : isNarrow
                ? NavigationBar(
                    selectedIndex: _pageIndex,
                    onDestinationSelected: _onDestinationSelected,
                    destinations: const [
                      NavigationDestination(
                          icon: Icon(Icons.menu_book), label: '阅读'),
                      NavigationDestination(
                          icon: Icon(Icons.person), label: '我的'),
                      NavigationDestination(
                          icon: Icon(Icons.settings), label: '设置'),
                    ],
                  )
                : null,
      ),
    );
  }

  Widget _buildFatalError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 56, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text('启动失败', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => SystemNavigator.pop(),
              child: const Text('退出应用'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_initError != null) {
      return _buildFatalError(_initError!);
    }
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_transitioning) {
      return IndexedStack(key: _bodyKey, index: _pageIndex, children: _pages);
    }
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: SlideTransition(
                position: _slideOut, child: _pages[_prevPageIndex]),
          ),
          Positioned.fill(
            child:
                SlideTransition(position: _slideIn, child: _pages[_pageIndex]),
          ),
        ],
      ),
    );
  }
}
