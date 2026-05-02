import 'dart:async';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/engine/recommendation.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 全局应用状态 — 等价于 QML AppViewModel
class AppState extends ChangeNotifier {
  NativeBridge? _bridge;
  late RecommendationEngine _engine;
  late KnowledgeTracker _tracker;

  User? _user;
  int _pageIndex = 0;
  int _previousPageIndex = 0;
  bool _darkMode = false;
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
  bool _readingRecorded = false;

  // ─── getters ──────────────────────────────────────────────────

  bool get initialized => _initialized;
  int get pageIndex => _pageIndex;
  bool get darkMode => _darkMode;
  String get logLevel => _logLevel;
  String? get error => _error;
  User? get user => _user;
  String get userName => _user?.name ?? '佚名';
  double get averageAbility => _user?.averageAbility ?? 0.3;
  List<ChineseText> get texts => _engine.texts;
  List<RecommendResult> get recommendations => _recommendations;
  ChineseText? get readingText => _readingText;
  List<String> get pages => _pages;
  int get currentPage => _currentPage;
  int get totalPages => _pages.isEmpty ? 0 : _pages.length;
  int get elapsedSeconds => _elapsedSeconds;
  bool get isReading => _readingText != null;

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

  Future<bool> initialize(String dbPath) async {
    if (_initialized) return true;

    try {
      final libPath = _resolveLibPath();
      _bridge = NativeBridge(libPath);

      final cPath = dbPath.toNativeUtf8();
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

  String _resolveLibPath() {
    if (Platform.isLinux) return '../build/libchinese_core.so';
    if (Platform.isMacOS) return '../build/libchinese_core.dylib';
    if (Platform.isWindows) return '../build/chinese_core.dll';
    return '../build/libchinese_core.so';
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

  @override
  void dispose() {
    _readingTimer?.cancel();
    _bridge?.dbClose();
    _user?.dispose();
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

  // ─── 阅读 ─────────────────────────────────────────────────────

  void loadTextForReading(int textId) {
    _readingText = _engine.getTextDetail(textId);
    _currentPage = 0;
    _pages = [];
    _elapsedSeconds = 0;
    _readingRecorded = false;
    _previousPageIndex = _pageIndex;
    _pageIndex = 2;
    notifyListeners();
  }

  void paginate(double pageWidth, double pageHeight) {
    if (_readingText == null) return;
    final content = _readingText!.content;
    if (content.isEmpty) {
      _pages = [];
      return;
    }

    final tp = TextPainter(
      text: TextSpan(text: content, style: AppTheme.bodyReading),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: pageWidth);
    final lineMetrics = tp.computeLineMetrics();

    const lineHeight = 18 * 1.8;
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
    _readingText = null;
    _pages = [];
    _currentPage = 0;
    _pageIndex = _previousPageIndex.clamp(0, 4);
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
    if (_readingTimer == null) return;
    if (_user != null &&
        _readingText != null &&
        _elapsedSeconds >= 30 &&
        !_readingRecorded) {
      _readingRecorded = true;
      final updated =
          _tracker.applyRead(_user!, _readingText!.id, _elapsedSeconds.toDouble());
      if (updated != null) {
        _user!.dispose();
        _user = updated;
      }
    }
    _readingTimer?.cancel();
    _readingTimer = null;
  }

  void switchPage(int index) {
    if (_pageIndex != index) {
      _pageIndex = index;
      notifyListeners();
    }
  }

  void recordReading(int textId, double seconds) {
    if (_user == null) return;
    final updated = _tracker.applyRead(_user!, textId, seconds);
    if (updated != null) {
      _user!.dispose();
      _user = updated;
      notifyListeners();
    }
  }

  // ─── 设置 ─────────────────────────────────────────────────────

  void setDarkMode(bool value) {
    _darkMode = value;
    notifyListeners();
  }

  void setLogLevel(String value) {
    _logLevel = value;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
