import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';
import 'package:chinese_classical_rec_sys/engine/update_checker.dart';
import 'package:chinese_classical_rec_sys/models/version.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

class SettingsController extends ChangeNotifier {
  bool _darkMode = false;
  bool _showTranslation = false;
  bool _showRuledLines = true;
  double _fontScale = 1.0;
  String _logLevel = defaultLogLevel;
  /// 用户主色（ARGB int，默认朱砂红 AppTheme.vermilion）
  int _accentColorValue = AppTheme.vermilion.toARGB32();
  String? _error;
  String? _notice;
  NativeBridge? _bridge;
  UpdateChecker? _updateChecker;
  SharedPreferences? _prefs;

  bool get darkMode => _darkMode;
  bool get showTranslation => _showTranslation;
  bool get showRuledLines => _showRuledLines;
  double get fontScale => _fontScale;
  String get logLevel => _logLevel;
  int get accentColorValue => _accentColorValue;
  String? get error => _error;
  String? get notice => _notice;
  String? get updateCheckError => _updateChecker?.lastErrorReason;

  void setDarkMode(bool value) {
    _darkMode = value;
    _prefs?.setBool('darkMode', value);
    notifyListeners();
  }

  void setShowTranslation(bool value) {
    _showTranslation = value;
    _prefs?.setBool('showTranslation', value);
    notifyListeners();
  }

  void setShowRuledLines(bool value) {
    _showRuledLines = value;
    _prefs?.setBool('showRuledLines', value);
    notifyListeners();
  }

  void setFontScale(double value) {
    _fontScale = SettingsController.fontScaleSteps
        .reduce((a, b) => (value - a).abs() < (value - b).abs() ? a : b);
    _prefs?.setDouble('fontScale', _fontScale);
    notifyListeners();
  }

  void setAccentColor(int colorValue) {
    _accentColorValue = colorValue;
    _prefs?.setInt('accentColor', colorValue);
    notifyListeners();
  }

  void setLogLevel(String value) {
    // A5：白名单归一（下拉项本身已是白名单，这里兜底程序化/脏输入，
    // 避免下拉的 value 与 items 不匹配而断言失败）。
    _logLevel = normalizeLogLevel(value);
    applyLogLevel(_bridge, _logLevel);
    _prefs?.setString('logLevel', _logLevel);
    notifyListeners();
  }

  /// logLevel 合法取值（A5 白名单，同时作为设置页下拉的取值域单一源）。
  static const List<String> logLevelOptions = ['INFO', 'DEBUG', 'WARN', 'ERROR'];

  /// 兜底级别：脏 prefs / 未知取值一律回退 INFO。
  static const String defaultLogLevel = 'INFO';

  /// 白名单归一（A5）：大小写不敏感，非法值回退 [defaultLogLevel]。
  ///
  /// 只归一到白名单，不做业务改写；[applyLogLevel] 的下发语义保持不变。
  static String normalizeLogLevel(String? raw) {
    final value = (raw ?? defaultLogLevel).toUpperCase();
    return logLevelOptions.contains(value) ? value : defaultLogLevel;
  }

  /// 把 `logLevel` 经既有 `log_set_level` 导出符号下发给 C++（零 ABI）。
  ///
  /// A3：`main.dart` 在 `coord.init`（`db_open` → `Logger::init`）之前先调用
  /// [applySavedLogLevel]，使启动段（DB 打开/内置数据升级/档案加载）也受用户级别控制；
  /// [init] 之后再下发一次，留下一条不被自身级别过滤的切换回执。
  /// 原样下发调用方给的值（归一在 [normalizeLogLevel] 完成，不在此静默改写）。
  static void applyLogLevel(NativeBridge? bridge, String level) {
    final ptr = level.toLowerCase().toNativeUtf8(allocator: calloc);
    try {
      bridge?.logSetLevel(ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  /// 从 prefs 读取 `logLevel`（缺失或非法时 INFO）并下发（A3 + A5）。
  static void applySavedLogLevel(SharedPreferences prefs, NativeBridge? bridge) {
    applyLogLevel(bridge, normalizeLogLevel(prefs.getString('logLevel')));
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void setError(String? message) {
    _error = message;
    notifyListeners();
  }

  void clearNotice() {
    _notice = null;
    notifyListeners();
  }

  void setNotice(String? message) {
    _notice = message;
    notifyListeners();
  }

  Future<void> init(SharedPreferences prefs, NativeBridge? bridge) async {
    _prefs = prefs;
    _bridge = bridge;
    _fontScale = prefs.getDouble('fontScale') ?? 1.0;
    _darkMode = prefs.getBool('darkMode') ?? false;
    _showTranslation = prefs.getBool('showTranslation') ?? false;
    _showRuledLines = prefs.getBool('showRuledLines') ?? true;
    _accentColorValue =
        prefs.getInt('accentColor') ?? AppTheme.vermilion.toARGB32();
    // A5：脏 prefs（如历史遗留/手改的非法值）回退 INFO，取值域收敛到白名单。
    final savedLevel = normalizeLogLevel(prefs.getString('logLevel'));
    _logLevel = savedLevel;
    applyLogLevel(bridge, savedLevel);
    _updateChecker = UpdateChecker(_prefs!);
  }

  Future<Version?> silentCheckForUpdates(String currentVersion) async {
    if (_updateChecker == null) return null;
    return _updateChecker!.checkSilently(currentVersion);
  }

  Future<Version?> manualCheckForUpdates(String currentVersion) async {
    if (_updateChecker == null) return null;
    return _updateChecker!.checkManually(currentVersion);
  }

  static const fontScaleSteps = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5];
}
