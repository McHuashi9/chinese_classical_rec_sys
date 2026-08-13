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
  String _logLevel = 'INFO';
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
    final savedLevel = prefs.getString('logLevel') ?? 'INFO';
    _logLevel = savedLevel;
    final cLevel = savedLevel.toLowerCase();
    final ptr = cLevel.toNativeUtf8(allocator: calloc);
    bridge?.logSetLevel(ptr);
    calloc.free(ptr);
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
