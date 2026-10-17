import 'dart:async';
import 'dart:ffi';
import 'dart:io' show File, Platform;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator, rootBundle;
import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bridge/ffi_bindings.dart';
import '../engine/app_logger.dart';
import '../engine/announcement.dart';
import '../engine/chinese_festivals.dart';
import '../engine/data_update_service.dart';
import '../engine/db_open_error_message.dart';
import '../engine/db_path_resolver.dart';
import '../state/coordinator.dart';
import '../state/settings_controller.dart';
import '../state/startup_controller.dart';
import '../theme/theme.dart';
import '../widgets/announcement_dialog.dart';
import '../widgets/dialogs.dart';
import '../widgets/festival_dialog.dart';
import '../widgets/profile_dialogs.dart';
import 'init_onboarding_page.dart';
import 'my_page.dart';
import 'read_hub_page.dart';
import 'settings_page.dart';
import 'welcome_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with TickerProviderStateMixin {
  late final List<Widget> _pages;

  bool _initialized = false;
  String? _initError;
  int _pageIndex = 0;
  int _prevPageIndex = 0;
  bool _transitioning = false;
  bool _isReading = false;
  AppCoordinator? _coord;
  StartupController? _startup;

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
      final coord = context.read<AppCoordinator>();
      _coord = coord;
      coord.initialized.addListener(_onInitChanged);
      coord.settingsCtrl.addListener(_onSettingsError);
      coord.readingCtrl.addListener(_onReadingChanged);
      coord.navCtrl.addListener(_onNavChanged);
      final startup = StartupController(
        driver: _MainShellStartupDriver(shell: this, coord: coord),
      );
      _startup = startup;
      startup.addListener(_onStartupChanged);
      unawaited(startup.start());
    });
  }

  Future<void> _maybeShowAnnouncement(SharedPreferences prefs) async {
    final announcement = await loadCurrentAnnouncement();
    if (announcement == null) return; // 无公告（asset 缺失/坏格式）→ 静默跳过
    final mode = loadAnnouncementMode(prefs);
    final seen = prefs.getString(kAnnouncementSeenIdKey);
    if (mode == AnnouncementMode.onUpdate && seen == announcement.id) {
      return;
    }
    if (!mounted) return;
    await AnnouncementDialog.show(
      context,
      announcement: announcement,
      initialMode: mode,
      onModeChanged: (m) async {
        await saveAnnouncementMode(prefs, m);
      },
    );
    await prefs.setString(kAnnouncementSeenIdKey, announcement.id);
  }

  Future<void> _maybeShowFestival() async {
    final festival = festivalForToday(DateTime.now());
    if (festival == null || !mounted) return;
    await FestivalDialog.show(context, festival: festival);
  }

  Future<bool> _showWelcome() async {
    if (!mounted) return false;
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const WelcomePage()),
    );
    return completed == true && mounted;
  }

  Future<void> _markWelcomeSeen(SharedPreferences prefs) async {
    await markNewUserWelcomeSeen(prefs);
    await markProfileOnboardingSeen(prefs);
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

  void _postInit(AppCoordinator coord, DataUpdateService dataUpdate) {
    _silentCheckForUpdates(coord).catchError((e, st) {
      AppLogger().error('silent check for updates failed: $e\n$st');
    });
    unawaited(dataUpdate.runSilentSync());
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

  void _onStartupChanged() {
    if (!mounted) return;
    final state = _startup!.state;
    if (state.isFatal) {
      setState(() => _initError = state.errorMessage ?? '启动失败，请重启应用。');
    }
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
      coord.settleReadingAfterDiscardChoice(discard: true);
      coord.navCtrl.switchPage(targetIndex);
    } else {
      coord.settleReadingAfterDiscardChoice(discard: false);
    }
  }

  void _onBackground() => _coord?.readingCtrl.pauseTimer();
  void _onForeground() => _coord?.readingCtrl.resumeTimer();

  Future<AppExitResponse> _onExitRequested() async {
    final coord = _coord;
    if (coord == null) return AppExitResponse.exit;

    coord.stopAndApplyReadingEffect();

    if (!coord.readingCtrl.hasUnrecordedReading) return AppExitResponse.exit;

    final discard = await showConfirmDialog(context,
        title: '确认退出',
        content: '当前文章未达到本文最低阅读时间，未完成追踪。确定要放弃当前阅读记录并退出吗？',
        confirmLabel: '放弃并退出');
    if (!context.mounted) return AppExitResponse.exit;
    coord.settleReadingAfterDiscardChoice(discard: discard);
    return discard ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  @override
  void dispose() {
    _startup?.removeListener(_onStartupChanged);
    _startup?.dispose();
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

    coord.stopAndApplyReadingEffect();

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
        coord.settleReadingAfterDiscardChoice(discard: false);
      }
      return;
    }

    final discard = await showConfirmDialog(
      context,
      title: '确认退出',
      content: '当前文章未达到本文最低阅读时间，未完成追踪。放弃并退出？',
      confirmLabel: '放弃并退出',
    );
    if (!context.mounted) return;
    coord.settleReadingAfterDiscardChoice(discard: discard);
    if (discard && context.mounted) {
      SystemNavigator.pop();
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

DynamicLibrary _loadCoreLibrary() {
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

/// 生产启动 driver：把 UI/DB/prefs 副作用封装在 MainShell 边界内，
/// 顺序、fatal 状态与 dispose 保护由 [StartupController] 负责。
class _MainShellStartupDriver implements StartupDriver {
  _MainShellStartupDriver({required this.shell, required this.coord});

  final _MainShellState shell;
  final AppCoordinator coord;

  SharedPreferences? _prefs;
  DbPathResolution? _resolution;
  DataUpdateService? _dataUpdate;
  bool _shouldShowWelcome = false;

  @override
  bool get shouldShowWelcome => _shouldShowWelcome;

  @override
  bool get needsInitGuide => !coord.userCtrl.isInitialized;

  @override
  Future<StartupPrepareResult> prepare() async {
    DynamicLibrary lib;
    try {
      lib = _loadCoreLibrary();
    } catch (e) {
      AppLogger().error('FFI load failed: $e');
      return const StartupPrepareResult.failure('无法加载核心组件，请尝试重新安装。');
    }
    final bridge = NativeBridge.fromLib(lib);
    // A3：级别下发前移——`coord.init` 里的 `db_open` 会触发 C++ `Logger::init`，
    // 先把 prefs 里保存的级别下发一次，启动段才受用户级别控制。
    final prefs = await SharedPreferences.getInstance();
    SettingsController.applySavedLogLevel(prefs, bridge);
    final resolution = await DbPathResolver(
      supportDirectoryProvider: getApplicationSupportDirectory,
      assetBytesLoader: (path) async {
        final data = await rootBundle.load(path);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      },
      assetStringLoader: (path) => rootBundle.loadString(path),
      dbReplace: bridge.dbReplaceUtf8,
    ).resolve();
    bool initOk;
    try {
      initOk =
          await coord.init(resolution.contentPath, resolution.userPath, lib);
    } catch (e) {
      AppLogger().error('数据库初始化失败: $e');
      AppLogger().flushPending();
      return const StartupPrepareResult.failure('数据库初始化失败，请重启应用。');
    }
    // A2：`coord.init` 已触发 C++ 日志 sink 初始化，此时回放桥未就绪期缓冲。
    AppLogger().flushPending();
    if (!initOk) {
      return StartupPrepareResult.failure(
          dbOpenErrorMessage(coord.dbOpenErrorCode));
    }
    _prefs = prefs;
    _resolution = resolution;
    // 在 activateSavedProfile 之前先判定，避免用 active_user_id 做“是否已引导”的标记。
    _shouldShowWelcome = shouldShowNewUserWelcome(
        prefs, coord.userCtrl.profiles, coord.userCtrl.isInitialized);
    return const StartupPrepareResult.ok();
  }

  @override
  Future<void> afterDatabaseReady() async {
    final prefs = _prefs!;
    final resolution = _resolution!;
    if (resolution.replaced) {
      coord.settingsCtrl.setNotice('内容已更新，学习进度已保留');
    }
    coord.setContentPathAfterSync(resolution.contentPath);

    final dbDir = File(resolution.contentPath).parent.path;
    final dataUpdate = DataUpdateService(
      prefs: prefs,
      dbDirPath: dbDir,
      syncRunner: (remoteVersion, downloadUrl) => coord.remoteSyncDb(
        remoteVersion: remoteVersion,
        downloadUrl: downloadUrl,
      ),
    );
    _dataUpdate = dataUpdate;
    coord.setContentDataVersion(await dataUpdate.readLocalDbVersion());
    coord.initRemoteDbSync(prefs, dbDir);
    coord.activateSavedProfile();
    coord.getRecommendations(10);
    await coord.settingsCtrl.init(prefs, coord.bridge);
  }

  @override
  Future<void> showAnnouncement() => shell._maybeShowAnnouncement(_prefs!);

  @override
  Future<void> showFestival() => shell._maybeShowFestival();

  @override
  Future<bool> showWelcome() => shell._showWelcome();

  @override
  Future<void> markWelcomeSeen() => shell._markWelcomeSeen(_prefs!);

  @override
  Future<void> showInitGuide() => shell._showInitGuide(coord);

  @override
  void postInit() => shell._postInit(coord, _dataUpdate!);
}
