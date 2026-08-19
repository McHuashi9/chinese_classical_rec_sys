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
import 'package:chinese_classical_rec_sys/engine/algorithm_constants.dart';
import 'package:chinese_classical_rec_sys/engine/profile_repository.dart';
import 'package:chinese_classical_rec_sys/engine/user_init_repository.dart';
import 'package:chinese_classical_rec_sys/engine/remote_db_sync.dart';
import 'package:chinese_classical_rec_sys/engine/annotation_parser.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/service/history_service.dart';
import 'package:chinese_classical_rec_sys/engine/app_logger.dart';

class AppCoordinator {
  static const currentVersion = '1.2.0';

  final NavigationController navCtrl;
  final SettingsController settingsCtrl;
  final ReadingController readingCtrl;
  final UserController userCtrl;
  final ReadTracker readTracker;

  final ValueNotifier<bool> initialized = ValueNotifier(false);

  /// 数据库替换窗口（引擎 g_state 关闭重开期间）为 true。
  /// 当前实现替换段内无 await（原子），该闸门是防御性的：
  /// 防未来在替换/回滚/重开之间插入异步间隙时，答题/阅读效应 FFI 调用落到
  /// 已关闭的引擎上静默 NOT_INIT。UI 侧（quiz 提交、阅读效应）据此短路。
  final ValueNotifier<bool> syncing = ValueNotifier(false);

  NativeBridge? _bridge;
  late TextRepository _textRepo;
  late RecommendationEngine _engine;
  late ProfileRepository _profileRepo;
  late UserInitRepository _initRepo;
  RemoteDbSync? _remoteDbSync;
  HistoryService? _historyService;
  SharedPreferences? _prefs;

  String? _contentPathAfterSync;
  String _contentDataVersion = 'unknown';
  int? _dbOpenErrorCode;

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

  String get contentDataVersion => _contentDataVersion;
  int? get dbOpenErrorCode => _dbOpenErrorCode;

  void setContentDataVersion(String version) {
    _contentDataVersion = version;
  }

  /// 双库 schema 版本（user_version / content_version）；未打开或失败返回 null。
  (int, int)? get schemaVersions {
    if (_bridge == null) return null;
    final uv = calloc<Int32>();
    final cv = calloc<Int32>();
    final rc = _bridge!.dbGetSchemaVersions(uv, cv);
    final result = rc == BridgeError.ok ? (uv.value, cv.value) : null;
    calloc.free(uv);
    calloc.free(cv);
    return result;
  }

  ChineseText? getTextDetail(int textId) =>
      isInitialized ? _textRepo.getTextDetail(textId) : null;

  String getAnnotations(int textId) =>
      isInitialized ? _textRepo.getAnnotations(textId) : '';

  String getTranslation(int textId) =>
      isInitialized ? _textRepo.getTranslation(textId) : '';

  /// 强制初始化使用的两篇短文（按标题匹配；缺失时返回空列表）。
  List<ChineseText> getInitTexts() {
    const titles = {'严先生祠堂记', '周郑交质'};
    return _textRepo.texts.where((t) => titles.contains(t.title)).toList();
  }

  Future<bool> init(String contentPath, String userPath, DynamicLibrary lib) async {
    if (isInitialized) return true;

    try {
      _bridge = NativeBridge.fromLib(lib);

      final cPath = contentPath.toNativeUtf8(allocator: calloc);
      final uPath = userPath.toNativeUtf8(allocator: calloc);
      final rc = _bridge!.dbOpen(cPath, uPath);
      calloc.free(cPath);
      calloc.free(uPath);

      if (rc != BridgeError.ok) {
        _dbOpenErrorCode = rc;
        settingsCtrl.setError('数据库打开失败: $contentPath / $userPath');
        return false;
      }
      _dbOpenErrorCode = null;

      _textRepo = TextRepository(_bridge!);
      _textRepo.loadTextCache();
      _engine = RecommendationEngine(_bridge!);
      _profileRepo = FfiProfileRepository(_bridge!);
      _initRepo = FfiUserInitRepository(_bridge!);

      final tracker = KnowledgeTracker(_bridge!);
      userCtrl.initTracker(tracker);
      userCtrl.initProfiles(_profileRepo);
      userCtrl.initUserInitRepository(_initRepo);
      _loadUser();
      userCtrl.refreshProfiles();
      userCtrl.refreshInitState();
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

  /// 加载引擎当前档案到内存用户；返回是否成功。
  /// [allowDefaultInit] 失败时是否回退"重置为默认能力"（仅启动/首次初始化场景安全；
  /// 切换档案场景必须传 false——否则会把刚切过来的新档案能力覆盖成默认值）
  bool _loadUser({bool allowDefaultInit = true}) {
    final u = User.allocate(calloc);
    final rc = _bridge!.userLoad(u.ptr);
    if (rc == BridgeError.ok) {
      userCtrl.setUser(u);
      return true;
    }
    u.dispose();
    if (allowDefaultInit) {
      _initDefaultUser();
    }
    return false;
  }

  void _initDefaultUser() {
    _bridge!.userInitDefault();
    _loadUser(allowDefaultInit: false);
  }

  /// 当前档案相关的内存态整体失效重建（切换档案 / 远程同步后共用）：
  /// 已读集合清空回填、档案列表、错题数缓存、阅读统计缓存、推荐列表。
  /// 新档案的 user 对象必须先由 [_loadUser] 载入。
  void _reloadUserScopedState() {
    readTracker.clear();
    _loadTextTrackedStates();
    userCtrl.refreshProfiles();
    userCtrl.invalidateQuizData();
    _cachedStats = null;
    _statsGeneration++;
    getRecommendations(10);
  }

  /// 启动时恢复上次档案（prefs active_user_id）；失败回退到引擎当前档案并落 prefs
  void activateSavedProfile() {
    final saved = _prefs?.getInt('active_user_id');
    if (saved != null && saved != userCtrl.activeUserId) {
      if (!switchProfile(saved)) {
        AppLogger().warn('启动恢复档案 $saved 失败，回退到当前档案 ${userCtrl.activeUserId}');
      }
    }
    userCtrl.refreshProfiles();
    final active = userCtrl.activeUserId;
    if (active != null) {
      _prefs?.setInt('active_user_id', active);
    }
  }

  /// 切换当前档案：C++ user_switch 重载用户 → 失效已读集合/推荐/统计缓存 → 重拉推荐。
  /// 加载新档案失败时切回原档案，避免"引擎已切、内存没切"的错位写库。
  bool switchProfile(int id) {
    if (!isInitialized || _bridge == null) return false;
    if (syncing.value) return false;
    if (id == userCtrl.activeUserId) return true;

    final oldId = userCtrl.activeUserId;
    final rc = _bridge!.userSwitch(id);
    if (rc != BridgeError.ok) return false;

    if (!_loadUser(allowDefaultInit: false)) {
      // 引擎已切到新档案但读取失败：绝不重置新档案，尝试切回原档案自愈
      AppLogger().warn('切换档案 $id 后加载用户失败，尝试切回 $oldId');
      if (oldId != null && _bridge!.userSwitch(oldId) == BridgeError.ok) {
        _loadUser();
      } else {
        settingsCtrl.setError('切换档案失败，请重启应用');
      }
      return false;
    }

    _reloadUserScopedState();
    _prefs?.setInt('active_user_id', id);
    return true;
  }

  /// 新建档案（不切换；UI 成功后调用 [switchProfile]）。
  /// 未初始化时 UserController 没有档案仓库，自然返回 null。
  int? createProfile(String name) {
    return userCtrl.createProfile(name);
  }

  /// 新建档案并继承已有档案能力与历史。
  int? createInheritedProfile(String name, int sourceId) {
    return userCtrl.createInheritedProfile(name, sourceId);
  }

  /// 重命名档案
  bool renameProfile(int id, String name) {
    return userCtrl.renameProfile(id, name);
  }

  /// 软删档案（拒绝删除当前档案）
  bool deleteProfile(int id) {
    if (id == userCtrl.activeUserId) return false;
    return userCtrl.deleteProfile(id);
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
    finishReadingSession();
    navCtrl.switchPage(targetPage.clamp(0, 2));
  }

  /// 结束当前活动阅读会话：停止计时 → 尝试结算阅读效应 → 丢弃阅读状态。
  /// 阅读时间不足时 applyReadingEffect 内部会跳过，仅丢弃状态。
  void finishReadingSession() {
    if (!readingCtrl.isReading) return;
    readingCtrl.stopTimer();
    applyReadingEffect();
    readingCtrl.discardReading();
  }

  /// 停止计时并尝试结算阅读效应，但保留阅读状态。
  ///
  /// 用于“退出/返回”等需要先结算、再根据是否达到阈值决定是否丢弃的路径；
  /// 确认丢弃后再调用 [ReadingController.discardReading]。
  void stopAndApplyReadingEffect() {
    if (!readingCtrl.isReading) return;
    readingCtrl.stopTimer();
    applyReadingEffect();
  }

  /// 用户在“退出/放弃”确认后的统一收尾。
  ///
  /// [discard] 为 true 时按 [finishReadingSession] 语义补结算并丢弃阅读状态；
  /// 为 false 时恢复计时（保留阅读状态，等待继续阅读）。
  /// 若调用方已先调用 [stopAndApplyReadingEffect]，此处重复结算幂等：
  /// [applyReadingEffect] 内部有已读标记，不会二次应用阅读效应。
  void settleReadingAfterDiscardChoice({required bool discard}) {
    if (discard) {
      finishReadingSession();
    } else {
      readingCtrl.resumeTimer();
    }
  }

  void applyReadingEffect() {
    // 替换窗口内引擎关闭：跳过阅读效应（防静默失败；当前窗口为原子段，正常不可达）
    if (syncing.value) return;
    final textId = readingCtrl.readingTextId;
    final seconds = readingCtrl.elapsedSeconds;
    final text = readingCtrl.readingText;
    if (textId != null &&
        userCtrl.user != null &&
        text != null &&
        !readTracker.isTextRead(textId) &&
        seconds >= minReadTimeSeconds(text.charCount)) {
      readTracker.markEffectApplied(textId);
      if (userCtrl.applyReadEffect(text.id, seconds.toDouble())) {
        _statsGeneration++;
      }
    }
  }

  /// 初始化阅读记录：无论阅读时长，只写 reading_history / text_tracking，
  /// 不应用能力效应（skip_effect=1）。成功后标记该篇已读，避免普通取题重复。
  bool recordInitRead(int textId, double seconds) {
    if (_bridge == null || userCtrl.user == null) return false;
    final outUser = User.allocate(calloc);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rc = _bridge!.trackerApplyRead(
        userCtrl.user!.ptr, textId, seconds, now, outUser.ptr, 1);
    outUser.dispose();
    if (rc != BridgeError.ok) return false;
    readTracker.markEffectApplied(textId);
    return true;
  }

  void getRecommendations(int topK) {
    if (!isInitialized) {
      settingsCtrl.setError('系统尚未初始化');
      return;
    }
    try {
      // 已读篇目不进推荐位（达到本文最低阅读时间且效应已应用）；UserController 侧过取+过滤补足 topK
      userCtrl.getRecommendations(_engine, _textRepo.texts, topK,
          excludeTextIds: readTracker.getAllTrackedIds().toSet());
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
    if (_bridge == null || !isInitialized || _contentPathAfterSync == null) {
      _deleteFile(tmpPath);
      return;
    }

    final contentPath = _contentPathAfterSync!;
    // 防御性闸门：db_replace 已不关引擎，仍防未来异步间隙。
    syncing.value = true;
    try {
      final rc = _replaceDb(tmpPath, contentPath);
      if (rc != BridgeError.ok) {
        AppLogger().error('remoteSyncDb: db_replace 失败 rc=$rc，已保留旧库');
        _deleteFile(tmpPath);
        // C++ 已内部回滚并保持旧内容挂载，无需重开引擎/恢复档案。
        settingsCtrl.setError('数据库同步失败，已保留当前数据。');
        return;
      }
      // 成功后：内容库已原子替换并重挂载，文本缓存失效重建；用户库/当前档案未动。
      _textRepo.loadTextCache();
      _reloadUserScopedState();
    } finally {
      syncing.value = false;
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
    settingsCtrl.setNotice('内容已更新，学习进度已保留');
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

  void _deleteFile(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // 清理失败不影响主流程
    }
  }

  void setContentPathAfterSync(String path) {
    _contentPathAfterSync = path;
  }

  void initRemoteDbSync(SharedPreferences prefs, String dbDirPath,
      {RemoteDbSync? remoteDbSync}) {
    _prefs = prefs;
    _remoteDbSync = remoteDbSync ?? RemoteDbSync(prefs, dbDirPath);
  }

  void dispose() {
    readingCtrl.dispose();
    userCtrl.dispose();
    _bridge?.dbClose();
    navCtrl.dispose();
    settingsCtrl.dispose();
    initialized.dispose();
    syncing.dispose();
  }
}
