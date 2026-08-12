import 'dart:async';
import 'dart:ffi';
import 'dart:io' show File;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/engine/recommendation.dart';
import 'package:chinese_classical_rec_sys/engine/text_repository.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/engine/remote_db_sync.dart';
import 'package:chinese_classical_rec_sys/engine/annotation_parser.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/service/history_service.dart';
import 'package:chinese_classical_rec_sys/engine/app_logger.dart';

class AppCoordinator {
  static const currentVersion = '0.9.2';

  final NavigationController navCtrl;
  final SettingsController settingsCtrl;
  final ReadingController readingCtrl;
  final UserController userCtrl;
  final ReadTracker readTracker;

  final ValueNotifier<bool> initialized = ValueNotifier(false);

  NativeBridge? _bridge;
  late TextRepository _textRepo;
  late RecommendationEngine _engine;
  RemoteDbSync? _remoteDbSync;
  HistoryService? _historyService;

  String? _dbPathAfterSync;

  ReadingStats? _cachedStats;
  int _statsGeneration = 0;
  int _statsEpoch = -1;

  AppCoordinator({
    required this.navCtrl,
    required this.settingsCtrl,
    required this.readingCtrl,
    required this.userCtrl,
    required this.readTracker,
  });

  NativeBridge? get bridge => _bridge;
  bool get isInitialized => initialized.value;
  List<ChineseText> get texts => isInitialized ? _textRepo.texts : [];
  HistoryService get history => _historyService!;

  ChineseText? getTextDetail(int textId) =>
      isInitialized ? _textRepo.getTextDetail(textId) : null;

  Future<bool> init(String dbPath, DynamicLibrary lib) async {
    if (isInitialized) return true;

    try {
      _bridge = NativeBridge.fromLib(lib);

      final cPath = dbPath.toNativeUtf8(allocator: calloc);
      final rc = _bridge!.dbOpen(cPath);
      calloc.free(cPath);

      if (rc != BridgeError.ok) {
        settingsCtrl.setError('数据库打开失败: $dbPath');
        return false;
      }

      _textRepo = TextRepository(_bridge!);
      _textRepo.loadTextCache();
      _engine = RecommendationEngine(_bridge!);

      final tracker = KnowledgeTracker(_bridge!);
      userCtrl.initTracker(tracker);
      _loadUser();
      _loadTextTrackedStates();
      _historyService = HistoryService(_bridge!, _textRepo);

      initialized.value = true;
      settingsCtrl.clearError();
      return true;
    } catch (e) {
      settingsCtrl.setError('初始化失败: $e');
      return false;
    }
  }

  void _loadUser({bool fromDefaultInit = false}) {
    final u = User.allocate(calloc);
    final rc = _bridge!.userLoad(u.ptr);
    if (rc == BridgeError.ok) {
      userCtrl.setUser(u);
    } else {
      u.dispose();
      if (!fromDefaultInit) {
        _initDefaultUser();
      }
    }
  }

  void _initDefaultUser() {
    _bridge!.userInitDefault();
    _loadUser(fromDefaultInit: true);
  }

  void _loadTextTrackedStates() {
    if (_bridge == null) return;
    const maxIds = 500;
    final idsPtr = calloc<Int32>(maxIds);
    final count = _bridge!.historyGetTrackedTextIds(idsPtr, maxIds);
    final ids = <int>[];
    for (int i = 0; i < count; i++) {
      ids.add(idsPtr[i]);
    }
    calloc.free(idsPtr);
    readTracker.loadFromIds(ids);
    if (count > 0) {
      AppLogger().info('启动回填: 已追踪 $count 篇文章');
    }
  }

  bool loadTextForReading(int textId) {
    final text = _textRepo.getTextDetail(textId);
    if (text == null) return false;
    final raw = _textRepo.getAnnotations(textId);
    final annotations = AnnotationParser.parse(raw);
    final translation = _textRepo.getTranslation(textId);
    readingCtrl.loadText(
      text,
      annotations: annotations,
      translation: translation,
      showTranslation: settingsCtrl.showTranslation,
    );
    return true;
  }

  void goHome(int targetPage) {
    readingCtrl.stopTimer();
    applyReadingEffect();
    readingCtrl.discardReading();
    navCtrl.switchPage(targetPage.clamp(0, 2));
  }

  void applyReadingEffect() {
    final textId = readingCtrl.readingTextId;
    final seconds = readingCtrl.elapsedSeconds;
    final text = readingCtrl.readingText;
    if (textId != null &&
        seconds >= 30 &&
        userCtrl.user != null &&
        text != null &&
        !readTracker.isTextRead(textId)) {
      readTracker.markEffectApplied(textId);
      if (userCtrl.applyReadEffect(text.id, seconds.toDouble())) {
        _statsGeneration++;
      }
    }
  }

  void getRecommendations(int topK) {
    if (!isInitialized) {
      settingsCtrl.setError('系统尚未初始化');
      return;
    }
    try {
      userCtrl.getRecommendations(_engine, _textRepo.texts, topK);
      settingsCtrl.clearError();
    } catch (e) {
      settingsCtrl.setError('推荐失败: $e');
    }
  }

  List<ReadingRecord> getRecentHistory() => history.getRecent(30);

  int getTotalReadCount() => history.getTotalCount();

  ReadingStats getReadingStats() {
    final cache = _cachedStats;
    if (cache != null && _statsGeneration == _statsEpoch) return cache;
    _cachedStats = HistoryService.computeStats(history.getRecent(9999));
    _statsEpoch = _statsGeneration;
    return _cachedStats!;
  }

  Future<void> remoteSyncDb({String? remoteVersion, String? downloadUrl}) async {
    if (remoteVersion == null || downloadUrl == null) return;
    if (_remoteDbSync == null) return;

    final tmpPath = await _remoteDbSync!.trySyncFromRelease(
      remoteVersion: remoteVersion,
      downloadUrl: downloadUrl,
    );
    if (tmpPath == null) return;
    if (_bridge == null || !isInitialized || _dbPathAfterSync == null) {
      _deleteFile(tmpPath);
      return;
    }

    final dbPath = _dbPathAfterSync!;
    final rc = _replaceDb(tmpPath, dbPath);
    if (rc != BridgeError.ok) {
      AppLogger().error('remoteSyncDb: db_replace 失败 rc=$rc，已保留旧库');
      _deleteFile(tmpPath);
      // db_replace 失败后引擎已关闭，必须重开旧库，否则本会话假死
      if (_openDb(dbPath) != BridgeError.ok) {
        AppLogger().error('remoteSyncDb: 失败后重开旧库失败，请重启');
        settingsCtrl.setError('数据库同步失败，已保留当前数据。请重启应用。');
        return;
      }
      settingsCtrl.setError('数据库同步失败，已保留当前数据。');
      return;
    }

    var restored = false;
    var openRc = _openDb(dbPath);
    if (openRc != BridgeError.ok) {
      AppLogger().error('remoteSyncDb: 重开新库失败 rc=$openRc，尝试回滚 .bak');
      await _restoreBak(dbPath);
      restored = true;
      openRc = _openDb(dbPath);
      if (openRc != BridgeError.ok) {
        _deleteFile(tmpPath);
        settingsCtrl.setError('数据库同步后无法打开数据库，请重启应用。');
        return;
      }
    }

    _textRepo.loadTextCache();
    _loadUser();
    _loadTextTrackedStates();
    if (restored) {
      // 内容实际未同步（已回滚旧库）：不写冷却标记、不提示成功
      AppLogger().warn('remoteSyncDb: 同步已回滚，恢复旧库');
      settingsCtrl.setError('数据库同步失败，已恢复原数据。');
      return;
    }

    // 先落版本号再写冷却：缩小"库已更新但版本文件未更新"的降级窗口
    try {
      await _remoteDbSync!.commitVersion(remoteVersion);
    } catch (e) {
      AppLogger().error('remoteSyncDb: 版本回写失败（下次启动可能被内置数据覆盖）: $e');
    }
    await _remoteDbSync!.markSynced();
    // 检查失败/替换失败都不会走到这里：只有真正同步成功才冷却检查
    await _remoteDbSync!.markChecked();
    AppLogger().info('remoteSyncDb: 同步完成 $remoteVersion，用户数据已保留');
    settingsCtrl.setNotice('数据已同步，学习进度已保留');
  }

  int _replaceDb(String newPath, String curPath) {
    if (_bridge == null) return -1;
    final np = newPath.toNativeUtf8(allocator: calloc);
    final cp = curPath.toNativeUtf8(allocator: calloc);
    final rc = _bridge!.dbReplace(np, cp);
    calloc.free(np);
    calloc.free(cp);
    return rc;
  }

  int _openDb(String path) {
    if (_bridge == null) return -1;
    final cp = path.toNativeUtf8(allocator: calloc);
    final rc = _bridge!.dbOpen(cp);
    calloc.free(cp);
    return rc;
  }

  Future<void> _restoreBak(String dbPath) async {
    try {
      final cur = File(dbPath);
      final bak = File('$dbPath.bak');
      if (await bak.exists()) {
        if (await cur.exists()) await cur.delete();
        await bak.rename(dbPath);
        AppLogger().info('remoteSyncDb: 已从 .bak 回滚数据库');
      }
    } catch (e) {
      AppLogger().error('remoteSyncDb: .bak 回滚失败: $e');
    }
  }

  void _deleteFile(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // 清理失败不影响主流程
    }
  }

  void setDbPathAfterSync(String path) {
    _dbPathAfterSync = path;
  }

  void initRemoteDbSync(SharedPreferences prefs, String dbDirPath) {
    _remoteDbSync = RemoteDbSync(prefs, dbDirPath);
  }

  void dispose() {
    readingCtrl.dispose();
    userCtrl.dispose();
    _bridge?.dbClose();
    navCtrl.dispose();
    settingsCtrl.dispose();
    initialized.dispose();
  }
}
