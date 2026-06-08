import 'dart:async';
import 'dart:ffi';
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
  static const currentVersion = '0.7.3';

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
    readingCtrl.loadText(text, annotations: annotations);
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
    _cachedStats = history.computeStats(history.getRecent(9999));
    _statsEpoch = _statsGeneration;
    return _cachedStats!;
  }

  Future<void> remoteSyncDb({String? remoteVersion, String? downloadUrl}) async {
    if (remoteVersion == null || downloadUrl == null) return;
    if (_remoteDbSync == null) return;
    final ok = await _remoteDbSync!.trySyncFromRelease(
      remoteVersion: remoteVersion,
      downloadUrl: downloadUrl,
    );
    if (ok && _bridge != null && isInitialized) {
      final originalPath = _dbPathAfterSync;
      _bridge!.dbClose();
      final cPath = originalPath?.toNativeUtf8(allocator: calloc);
      if (cPath == null) {
        AppLogger().error('remoteSyncDb: toNativeUtf8 分配失败');
        settingsCtrl.setError('数据库同步失败：内存不足。请重启应用。');
        return;
      }
      final rc = _bridge!.dbOpen(cPath);
      calloc.free(cPath);
      if (rc != BridgeError.ok) {
        AppLogger().error('remoteSyncDb: dbOpen 返回错误码 $rc，尝试恢复旧连接');
        final oldPath = originalPath?.toNativeUtf8(allocator: calloc);
        if (oldPath != null) {
          _bridge!.dbOpen(oldPath);
          calloc.free(oldPath);
        }
        settingsCtrl.setError('数据库同步后无法打开新文件，已恢复旧数据库。');
        return;
      }
      _textRepo.loadTextCache();
      _loadUser();
      _loadTextTrackedStates();
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
