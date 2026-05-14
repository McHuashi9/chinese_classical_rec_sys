import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/engine/recommendation.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/engine/update_checker.dart';
import 'package:chinese_classical_rec_sys/engine/remote_db_sync.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/models/version.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/service/history_service.dart';
import 'package:chinese_classical_rec_sys/engine/app_logger.dart';

/// 单篇文章的阅读计时状态
class _TextReadState {
  int totalSeconds = 0;
  bool effectApplied = false;
}

/// 全局应用状态 — 等价于 QML AppViewModel
class AppState extends ChangeNotifier {
  static const currentVersion = '0.5.0';

  NativeBridge? _bridge;
  late RecommendationEngine _engine;
  late KnowledgeTracker _tracker;
  UpdateChecker? _updateChecker;
  RemoteDbSync? _remoteDbSync;
  SharedPreferences? _prefs;
  HistoryService? _historyService;

  User? _user;
  int _pageIndex = 0;
  int _previousPageIndex = 0;
  bool _darkMode = false;
  double _fontScale = 1.0;
  String _logLevel = 'INFO';
  bool _initialized = false;
  String? _error;

  // 推荐 & 阅读状态
  List<RecommendResult> _recommendations = [];
  ChineseText? _readingText;
  List<String> _pages = [];
  int _currentPage = 0;

  // 阅读计时器
  Timer? _readingTimer;
  int _elapsedSeconds = 0;
  int? _readingTextId;

  // per-text 阅读状态
  final Map<int, _TextReadState> _textReadStates = {};

  // ─── getters ──────────────────────────────────────────────────

  bool get initialized => _initialized;
  int get pageIndex => _pageIndex;
  bool get darkMode => _darkMode;
  double get fontScale => _fontScale;
  String get logLevel => _logLevel;
  String? get error => _error;
  void setError(String? message) { _error = message; notifyListeners(); }
  User? get user => _user;
  double get averageAbility => _user?.averageAbility ?? 0.3;
  List<ChineseText> get texts => _initialized ? _engine.texts : [];
  List<RecommendResult> get recommendations => _recommendations;
  ChineseText? get readingText => _readingText;
  List<String> get pages => _pages;
  int get currentPage => _currentPage;
  int get totalPages => _pages.isEmpty ? 0 : _pages.length;
  int get elapsedSeconds => _elapsedSeconds;
  bool get isReading => _readingText != null;
  HistoryService get history => _historyService!;

  bool isTextRead(int textId) =>
      _textReadStates[textId]?.effectApplied ?? false;

  bool get hasUnrecordedReading {
    if (_readingTextId == null) return false;
    final state = _textReadStates[_readingTextId];
    if (state == null) return false;
    return !state.effectApplied;
  }

  String get formattedReadingTime {
    final m = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get currentPageNumberLabel {
    if (_pages.isEmpty) return '';
    return '第 ${_currentPage + 1} / ${_pages.length} 页';
  }

  // ─── 生命周期 ─────────────────────────────────────────────────

  Future<bool> initialize(String dbPath, DynamicLibrary lib) async {
    if (_initialized) return true;

    try {
      _bridge = NativeBridge.fromLib(lib);

      final cPath = dbPath.toNativeUtf8(allocator: calloc);
      final rc = _bridge!.dbOpen(cPath);
      calloc.free(cPath);

      if (rc != BridgeError.ok) {
        _error = '数据库打开失败: $dbPath';
        notifyListeners();
        return false;
      }

      _engine = RecommendationEngine(_bridge!);
      _engine.loadTextCache();

      _tracker = KnowledgeTracker(_bridge!);
      _loadUser();
      _loadTextTrackedStates();
      _historyService = HistoryService(_bridge!, _engine);

      _initialized = true;
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = '初始化失败: $e';
      notifyListeners();
      return false;
    }
  }

  void _loadUser() {
    final u = User.allocate(calloc);
    final rc = _bridge!.userLoad(u.ptr);
    if (rc == BridgeError.ok) {
      _user = u;
    } else {
      u.dispose();
      _initDefaultUser();
    }
  }

  void _initDefaultUser() {
    _bridge!.userInitDefault();
    _loadUser();
  }

  void _loadTextTrackedStates() {
    if (_bridge == null) return;
    const maxIds = 2000;
    final idsPtr = calloc<Int32>(maxIds);
    final count = _bridge!.historyGetTrackedTextIds(idsPtr, maxIds);
    for (int i = 0; i < count; i++) {
      final textId = idsPtr[i];
      _textReadStates[textId] = _TextReadState()
        ..effectApplied = true;
    }
    calloc.free(idsPtr);
    if (count > 0) {
      AppLogger().info('启动回填: 已追踪 $count 篇文章');
    }
  }

  @override
  void dispose() {
    _readingTimer?.cancel();
    _bridge?.dbClose();
    _user?.dispose();
    // _historyService holds no resources to dispose
    super.dispose();
  }

  // ─── 推荐 ─────────────────────────────────────────────────────

  void getRecommendations(int topK) {
    if (_user == null) return;
    try {
      _recommendations = _engine.getRecommendations(_user!, topK);
      _error = null;
    } catch (e) {
      _error = '推荐失败: $e';
    }
    notifyListeners();
  }

  // ─── 历史 ─────────────────────────────────────────────────────

  List<ReadingRecord> getRecentHistory() => history.getRecent(30);

  int getTotalReadCount() => history.getTotalCount();

  ReadingStats getReadingStats() => history.computeStats(history.getRecent(9999));

  // ─── 阅读 ─────────────────────────────────────────────────────

  ChineseText? getTextDetail(int textId) => _engine.getTextDetail(textId);

  bool loadTextForReading(int textId) {
    final text = _engine.getTextDetail(textId);
    if (text == null) return false;

    if (_readingTextId != null) {
      _textReadStates.putIfAbsent(_readingTextId!, () => _TextReadState());
      _textReadStates[_readingTextId!]!.totalSeconds = _elapsedSeconds;
    }

    _readingTimer?.cancel();
    _readingTimer = null;

    _readingText = text;
    _readingTextId = textId;
    _currentPage = 0;
    _pages = [];

    _textReadStates.putIfAbsent(textId, () => _TextReadState());
    _elapsedSeconds = 0;

    startReadingTimer();
    notifyListeners();
    return true;
  }

  void paginate(double pageWidth, double pageHeight, ScreenSize screenSize) {
    if (_readingText == null) return;
    final content = _readingText!.content;
    if (content.isEmpty) {
      _pages = [];
      return;
    }

    final bodyStyle = AppTheme.bodyReadingSize(screenSize, _fontScale);
    final tp = TextPainter(
      text: TextSpan(text: content, style: bodyStyle),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: pageWidth);
    final lineMetrics = tp.computeLineMetrics();

    final lineHeight = bodyStyle.fontSize! * bodyStyle.height!;
    final linesPerPage = (pageHeight / lineHeight).floor();
    if (linesPerPage <= 0 || lineMetrics.isEmpty) {
      _pages = [content];
      _currentPage = 0;
      notifyListeners();
      return;
    }

    _pages = _splitIntoPages(tp, lineMetrics, linesPerPage, content);
    _currentPage = _currentPage.clamp(0, _pages.length - 1);
    notifyListeners();
  }

  List<String> _splitIntoPages(
    TextPainter tp,
    List<LineMetrics> lineMetrics,
    int linesPerPage,
    String content,
  ) {
    final result = <String>[];
    for (int startLine = 0; startLine < lineMetrics.length; startLine += linesPerPage) {
      final startOffset = startLine == 0
          ? 0
          : _getLineStartOffset(tp, lineMetrics, startLine);
      final endLine = (startLine + linesPerPage - 1).clamp(0, lineMetrics.length - 1);
      final endOffset = tp.getPositionForOffset(
        Offset(tp.width, lineMetrics[endLine].baseline),
      ).offset;
      result.add(content.substring(startOffset, endOffset).trimRight());
    }
    return result;
  }

  int _getLineStartOffset(
    TextPainter tp,
    List<LineMetrics> lineMetrics,
    int lineIndex,
  ) {
    if (lineIndex <= 0) return 0;
    final pos = tp.getPositionForOffset(
      Offset(0, lineMetrics[lineIndex].baseline),
    );
    return pos.offset;
  }

  void nextPage() {
    if (_currentPage < _pages.length - 1) {
      _currentPage++;
      notifyListeners();
    }
  }

  void prevPage() {
    if (_currentPage > 0) {
      _currentPage--;
      notifyListeners();
    }
  }

  void goHome() {
    stopReadingTimer();
    applyReadingEffect();
    _readingText = null;
    _readingTextId = null;
    _pages = [];
    _currentPage = 0;
    _elapsedSeconds = 0;
    _pageIndex = _previousPageIndex.clamp(0, 2);
    notifyListeners();
  }

  void startReadingTimer() {
    if (_readingTimer != null) return;
    _readingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedSeconds++;
      notifyListeners();
    });
  }

  void stopReadingTimer() {
    _readingTimer?.cancel();
    _readingTimer = null;

    if (_readingTextId == null) return;

    final state = _textReadStates[_readingTextId];
    if (state != null) {
      state.totalSeconds = _elapsedSeconds;
    }
  }

  void applyReadingEffect() {
    final state = _readingTextId != null ? _textReadStates[_readingTextId] : null;
    if (_elapsedSeconds >= 30 &&
        _user != null &&
        _readingText != null &&
        state != null &&
        !state.effectApplied) {
      state.effectApplied = true;
      final updated =
          _tracker.applyRead(_user!, _readingText!.id, _elapsedSeconds.toDouble());
      if (updated != null) {
        _user!.dispose();
        _user = _tracker.prune(updated);
        updated.dispose();
      }
    }
  }

  void pauseReadingTimer() {
    _readingTimer?.cancel();
    _readingTimer = null;
  }

  void resumeReadingTimer() {
    if (_readingTimer != null) return;
    _readingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedSeconds++;
      notifyListeners();
    });
  }

  void discardCurrentReading() {
    _readingText = null;
    _readingTextId = null;
    _pages = [];
    _currentPage = 0;
    _elapsedSeconds = 0;
    _readingTimer?.cancel();
    _readingTimer = null;
    notifyListeners();
  }

  void switchPage(int index) {
    if (_pageIndex != index) {
      _previousPageIndex = _pageIndex;
      _pageIndex = index;
      notifyListeners();
    }
  }

  void recordReading(int textId, double seconds) {
    if (_user == null) return;
    final updated = _tracker.applyRead(_user!, textId, seconds);
    if (updated != null) {
      _user!.dispose();
      _user = _tracker.prune(updated);
      updated.dispose();
      _textReadStates.putIfAbsent(textId, () => _TextReadState());
      _textReadStates[textId]!.effectApplied = true;
      notifyListeners();
    }
  }

  // ─── 设置 ─────────────────────────────────────────────────────

  void setDarkMode(bool value) {
    _darkMode = value;
    notifyListeners();
  }

  void setFontScale(double value) {
    _fontScale = value;
    _prefs?.setDouble('fontScale', value);
    notifyListeners();
  }

  void setLogLevel(String value) {
    _logLevel = value;
    final cLevel = value.toLowerCase();
    final ptr = cLevel.toNativeUtf8(allocator: calloc);
    _bridge?.logSetLevel(ptr);
    calloc.free(ptr);
    _prefs?.setString('logLevel', value);
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> initUpdateChecker() async {
    _prefs = await SharedPreferences.getInstance();
    _fontScale = _prefs?.getDouble('fontScale') ?? 1.0;
    final savedLevel = _prefs?.getString('logLevel') ?? 'INFO';
    setLogLevel(savedLevel);
    _updateChecker = UpdateChecker(_prefs!);
  }

  Future<Version?> silentCheckForUpdates() async {
    if (_updateChecker == null) return null;
    return _updateChecker!.checkSilently(currentVersion);
  }

  Future<Version?> manualCheckForUpdates() async {
    if (_updateChecker == null) return null;
    return _updateChecker!.checkManually(currentVersion);
  }

  Future<void> remoteSyncDb({String? remoteVersion, String? downloadUrl}) async {
    if (remoteVersion == null || downloadUrl == null) return;
    if (_remoteDbSync == null) return;
    final ok = await _remoteDbSync!.trySyncFromRelease(
      remoteVersion: remoteVersion,
      downloadUrl: downloadUrl,
    );
    if (ok && _bridge != null && _initialized) {
      _bridge!.dbClose();
      final cPath = _dbPathAfterSync?.toNativeUtf8(allocator: calloc);
      if (cPath != null) {
        _bridge!.dbOpen(cPath);
        calloc.free(cPath);
        _engine.loadTextCache();
        _loadUser();
        _loadTextTrackedStates();
        notifyListeners();
      }
    }
  }

  String? _dbPathAfterSync;

  void setDbPathAfterSync(String path) {
    _dbPathAfterSync = path;
  }

  void initRemoteDbSync(SharedPreferences prefs, String dbDirPath) {
    _remoteDbSync = RemoteDbSync(prefs, dbDirPath);
  }
}
