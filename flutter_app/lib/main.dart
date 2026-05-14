import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show File, Platform;
import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator, rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart' show getApplicationSupportDirectory;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'state/app_state.dart';
import 'engine/update_checker.dart';
import 'theme/theme.dart';
import 'engine/app_logger.dart';
import 'pages/read_hub_page.dart';
import 'pages/my_page.dart';
import 'pages/settings_page.dart';
import 'widgets/dialogs.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
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
      final isDark = context.select((AppState a) => a.darkMode);
      final fontScale = context.select((AppState a) => a.fontScale);

      return MaterialApp(
        title: '文言文推荐系统',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(screenSize, fontScale),
        darkTheme: AppTheme.darkTheme(screenSize, fontScale),
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
  static final _pages = <Widget>[
    const RepaintBoundary(child: ReadHubPage()),   // 0 阅读
    const RepaintBoundary(child: MyPage()),         // 1 我的
    const RepaintBoundary(child: SettingsPage()),   // 2 设置
  ];

  bool _initialized = false;
  int _pageIndex = 0;
  int _prevPageIndex = 0;
  bool _transitioning = false;
  bool _isReading = false;
  AppState? _app;

  late final AnimationController _ctrl;
  late Animation<Offset> _slideOut;
  late Animation<Offset> _slideIn;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
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
      _app = context.read<AppState>();
      _app!.addListener(_onAppStateChanged);
      _initApp(_app!);
    });
  }

  Future<void> _initApp(AppState app) async {
    final dbPath = await _resolveDbPath();
    try {
      final lib = _loadLibrary();
      await app.initialize(dbPath, lib);
    } catch (e) {
      AppLogger().error('FFI load failed: $e');
      if (!mounted) return;
      app.setError('无法加载核心组件，请尝试重新安装。\n$e');
      return;
    }
    if (!mounted) return;
    app.setDbPathAfterSync(dbPath);
    app.getRecommendations(10);

    final prefs = await SharedPreferences.getInstance();
    final dbDir = File(dbPath).parent.path;
    app.initRemoteDbSync(prefs, dbDir);
    await app.initUpdateChecker();
    _postInit(app);
  }

  void _postInit(AppState app) {
    unawaited(_silentCheckForUpdates(app));
    unawaited(_silentRemoteDbSync(app));
  }

  Future<void> _silentCheckForUpdates(AppState app) async {
    final latest = await app.silentCheckForUpdates();
    if (latest != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('发现新版本 v$latest（当前 ${AppState.currentVersion}）'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: '查看',
            onPressed: () {
              app.switchPage(2);
            },
          ),
        ),
      );
    }
  }

  Future<void> _silentRemoteDbSync(AppState app) async {
    final asset = await _fetchLatestReleaseAsset();
    if (asset != null) {
      await _syncIfNewer(app, asset.$1, asset.$2);
    }
  }

  Future<(String, String)?> _fetchLatestReleaseAsset() async {
    final prefs = await SharedPreferences.getInstance();
    final checker = UpdateChecker(prefs);
    final latestVersion = await checker.checkSilently(AppState.currentVersion);
    if (latestVersion == null) return null;

    final releaseUrl = 'https://api.github.com/repos/McHuashi9/'
        'chinese_classical_rec_sys/releases/tags/v$latestVersion';
    final resp = await http.get(Uri.parse(releaseUrl), headers: {
      'Accept': 'application/vnd.github.v3+json',
    });
    if (resp.statusCode != 200) return null;

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final assets = data['assets'] as List<dynamic>?;
    if (assets == null) return null;

    for (final a in assets) {
      final map = a as Map<String, dynamic>;
      final name = map['name'] as String?;
      if (name == 'classical.db' || name == 'classical.db.gz') {
        final url = map['browser_download_url'] as String?;
        if (url != null) return (latestVersion.toString(), url);
      }
    }
    return null;
  }

  Future<void> _syncIfNewer(AppState app, String version, String url) async {
    try {
      await app.remoteSyncDb(remoteVersion: 'v$version', downloadUrl: url);
    } catch (_) {}
  }

  Future<String> _resolveDbPath() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final dbPath = '${dir.path}/classical.db';
      final verPath = '${dir.path}/db_version.txt';
      final dbFile = File(dbPath);

      if (!await dbFile.exists()) {
        final data = await rootBundle.load('assets/data/classical.db');
        await dbFile.writeAsBytes(data.buffer.asUint8List());
        final assetVer = await _readAssetDbVersion();
        await File(verPath).writeAsString(assetVer);
      } else {
        final assetVer = await _readAssetDbVersion();
        String localVer = '';
        try {
          localVer = (await File(verPath).readAsString()).trim();
        } catch (_) {}
        if (localVer != assetVer) {
          final tmp = File('${dir.path}/classical.db.tmp');
          final data = await rootBundle.load('assets/data/classical.db');
          await tmp.writeAsBytes(data.buffer.asUint8List());
          final bak = File('${dir.path}/classical.db.bak');
          if (await bak.exists()) await bak.delete();
          await dbFile.rename(bak.path);
          await tmp.rename(dbPath);
          await File(verPath).writeAsString(assetVer);
          AppLogger().info('DB 已更新: $localVer → $assetVer');
        }
      }
      return dbPath;
    } catch (e) {
      AppLogger().warn('_resolveDbPath 失败: $e，回退到相对路径');
      return '../data/classical.db';
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

  void _onAppStateChanged() {
    final app = _app;
    if (app == null) return;
    if (app.error != null) {
      final errorMsg = app.error!;
      app.clearError();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (!_initialized && app.initialized) {
      setState(() => _initialized = true);
    }
    if (app.isReading != _isReading) {
      _isReading = app.isReading;
      setState(() {});
    }
    if (app.pageIndex != _pageIndex) {
      _prevPageIndex = _pageIndex;
      _pageIndex = app.pageIndex;
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
    final app = _app;
    if (app != null && app.isReading && index != 0) {
      _showAbandonDialog(index);
      return;
    }
    _app?.switchPage(index);
  }

  Future<void> _showAbandonDialog(int targetIndex) async {
    final app = _app!;
    app.pauseReadingTimer();
    final discard = await showConfirmDialog(context,
      title: '放弃阅读？',
      content: '阅读中切换页面将放弃当前记录。确定吗？',
      confirmLabel: '放弃',
    );
    if (discard) {
      app.stopReadingTimer();
      app.applyReadingEffect();
      app.discardCurrentReading();
      app.switchPage(targetIndex);
    } else {
      app.resumeReadingTimer();
    }
  }

  void _onBackground() => _app?.pauseReadingTimer();
  void _onForeground() => _app?.resumeReadingTimer();

  Future<AppExitResponse> _onExitRequested() async {
    final app = _app;
    if (app == null) return AppExitResponse.exit;

    app.stopReadingTimer();
    app.applyReadingEffect();

    if (!app.hasUnrecordedReading) return AppExitResponse.exit;

    final discard = await showConfirmDialog(context, title: '确认退出', content: '当前文章阅读未满30秒，未完成追踪。确定要放弃当前阅读记录并退出吗？', confirmLabel: '放弃并退出');
    if (!context.mounted) return AppExitResponse.exit;
    if (discard) {
      app.discardCurrentReading();
    } else {
      app.resumeReadingTimer();
    }
    return discard ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  @override
  void dispose() {
    _app?.removeListener(_onAppStateChanged);
    _ctrl.dispose();
    _lifecycleListener.dispose();
    super.dispose();
  }

  Future<void> _onBackPressed(bool didPop, _) async {
    if (didPop) return;
    final app = _app;
    if (app == null || !app.isReading) {
      final exit = await showConfirmDialog(context,
        title: '确认退出', content: '确定要退出应用吗？', confirmLabel: '退出',
      );
      if (exit && context.mounted) SystemNavigator.pop();
      return;
    }

    app.stopReadingTimer();
    app.applyReadingEffect();

    if (!app.hasUnrecordedReading) {
      final exit = await showConfirmDialog(context,
        title: '确认退出', content: '确定要退出应用吗？', confirmLabel: '退出',
      );
      if (exit && context.mounted) {
        SystemNavigator.pop();
      } else {
        app.resumeReadingTimer();
      }
      return;
    }

    final discard = await showConfirmDialog(context,
      title: '确认退出',
      content: '当前文章阅读未满30秒，未完成追踪。放弃并退出？',
      confirmLabel: '放弃并退出',
    );
    if (!context.mounted) return;
    if (discard) {
      app.discardCurrentReading();
      SystemNavigator.pop();
    } else {
      app.resumeReadingTimer();
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

  Widget _buildBody() {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_transitioning) {
      return IndexedStack(
          key: _bodyKey, index: _pageIndex, children: _pages);
    }
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: SlideTransition(
                position: _slideOut, child: _pages[_prevPageIndex]),
          ),
          Positioned.fill(
            child: SlideTransition(
                position: _slideIn, child: _pages[_pageIndex]),
          ),
        ],
      ),
    );
  }
}
