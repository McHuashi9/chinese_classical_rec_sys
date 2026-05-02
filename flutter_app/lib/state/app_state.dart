import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/engine/recommendation.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';

/// 全局应用状态 — 等价于 QML AppViewModel
class AppState extends ChangeNotifier {
  NativeBridge? _bridge;
  late RecommendationEngine _engine;
  late KnowledgeTracker _tracker;

  User? _user;
  bool _darkMode = false;
  bool _initialized = false;
  String? _error;

  // 推荐 & 阅读状态
  List<RecommendResult> _recommendations = [];
  ChineseText? _readingText;
  int _readingPage = 0;
  int _totalPages = 1;

  // ─── getters ──────────────────────────────────────────────────

  bool get initialized => _initialized;
  bool get darkMode => _darkMode;
  String? get error => _error;
  User? get user => _user;
  String get userName => _user?.name ?? '佚名';
  double get averageAbility => _user?.averageAbility ?? 0.3;
  List<ChineseText> get texts => _engine.texts;
  List<RecommendResult> get recommendations => _recommendations;
  ChineseText? get readingText => _readingText;
  int get readingPage => _readingPage;

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
    if (Platform.isLinux) return 'libchinese_core.so';
    if (Platform.isMacOS) return 'libchinese_core.dylib';
    if (Platform.isWindows) return 'chinese_core.dll';
    return 'libchinese_core.so';
  }

  void _loadUser() {
    final ptr = User.allocate(calloc);
    final rc = _bridge!.userLoad(ptr._ptr);
    if (rc == BridgeError.ok) {
      _user = ptr;
    } else {
      ptr.dispose();
      _initDefaultUser();
    }
  }

  void _initDefaultUser() {
    _bridge!.userInitDefault();
    _loadUser();
  }

  @override
  void dispose() {
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
    _readingPage = 0;
    _totalPages = 1;
    notifyListeners();
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

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
