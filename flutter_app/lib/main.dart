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
import 'state/coordinator.dart';
import 'state/navigation_controller.dart';
import 'state/settings_controller.dart';
import 'state/reading_controller.dart';
import 'state/user_controller.dart';
import 'engine/read_tracker.dart';
import 'engine/update_checker.dart';
import 'engine/github_config.dart';
import 'theme/theme.dart';
import 'engine/app_logger.dart';
import 'pages/read_hub_page.dart';
import 'pages/my_page.dart';
import 'pages/settings_page.dart';
import 'widgets/dialogs.dart';

void main() {
  final readTracker = ReadTracker();
  final navCtrl = NavigationController();
  final settingsCtrl = SettingsController();
  final readingCtrl = ReadingController(readTracker);
  final userCtrl = UserController(readTracker);
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
  late final List<Widget> _pages;

  bool _initialized = false;
  int _pageIndex = 0;
  int _prevPageIndex = 0;
  bool _transitioning = false;
  bool _isReading = false;
  AppCoordinator? _coord;

  late final AnimationController _ctrl;
  late Animation<Offset> _slideOut;
  late Animation<Offset> _slideIn;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _pages = <Widget>[
      const RepaintBoundary(child: ReadHubPage()),   // 0 阅读
      const RepaintBoundary(child: MyPage()),         // 1 我的
      const RepaintBoundary(child: SettingsPage()),   // 2 设置
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
    final dbPath = await _resolveDbPath();
    try {
      final lib = _loadLibrary();
      await coord.init(dbPath, lib);
    } catch (e) {
      AppLogger().error('FFI load failed: $e');
      if (!mounted) return;
      coord.settingsCtrl.setError('无法加载核心组件，请尝试重新安装。\n$e');
      return;
    }
    if (!mounted) return;
    coord.setDbPathAfterSync(dbPath);
    coord.getRecommendations(10);

    final prefs = await SharedPreferences.getInstance();
    final dbDir = File(dbPath).parent.path;
    coord.initRemoteDbSync(prefs, dbDir);
    await coord.settingsCtrl.init(prefs, null);
    _postInit(coord);
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
    final latest = await coord.settingsCtrl.silentCheckForUpdates(AppCoordinator.currentVersion);
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
    final asset = await _fetchLatestReleaseAsset();
    if (asset != null) {
      await _syncIfNewer(coord, asset.$1, asset.$2);
    }
  }

  Future<(String, String)?> _fetchLatestReleaseAsset() async {
    final prefs = await SharedPreferences.getInstance();
    final checker = UpdateChecker(prefs);
    final latestVersion = await checker.checkSilently(AppCoordinator.currentVersion);
    if (latestVersion == null) return null;

    final releaseUrl = GithubConfig.releaseApiByVersion(latestVersion.toString());
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

  Future<void> _syncIfNewer(AppCoordinator coord, String version, String url) async {
    try {
      await coord.remoteSyncDb(remoteVersion: 'v$version', downloadUrl: url);
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

  void _onInitChanged() {
    if (_coord!.initialized.value && !_initialized) {
      setState(() => _initialized = true);
    }
  }

  void _onSettingsError() {
    final error = _coord!.settingsCtrl.error;
    if (error != null) {
      _coord!.settingsCtrl.clearError();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
    final discard = await showConfirmDialog(context,
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

    final discard = await showConfirmDialog(context, title: '确认退出', content: '当前文章阅读未满30秒，未完成追踪。确定要放弃当前阅读记录并退出吗？', confirmLabel: '放弃并退出');
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
      final exit = await showConfirmDialog(context,
        title: '确认退出', content: '确定要退出应用吗？', confirmLabel: '退出',
      );
      if (exit && context.mounted) SystemNavigator.pop();
      return;
    }

    coord.readingCtrl.stopTimer();
    coord.applyReadingEffect();

    if (!coord.readingCtrl.hasUnrecordedReading) {
      final exit = await showConfirmDialog(context,
        title: '确认退出', content: '确定要退出应用吗？', confirmLabel: '退出',
      );
      if (exit && context.mounted) {
        SystemNavigator.pop();
      } else {
        coord.readingCtrl.resumeTimer();
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
