import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import '../bridge/ffi_bindings.dart';

class AppLogger {
  static AppLogger? _instance;
  AppLogger._();
  factory AppLogger() => _instance ??= AppLogger._();

  NativeBridge? get _bridge => NativeBridge.instance;

  void _log(int level, String message) {
    final bridge = _bridge;
    if (bridge == null) {
      debugPrint('[${_levelTag(level)}] $message');
      return;
    }
    final msg = message.toNativeUtf8();
    bridge.logWrite(level, msg);
    calloc.free(msg);
  }

  void debug(String msg) => _log(0, msg);
  void info(String msg)  => _log(1, msg);
  void warn(String msg)  => _log(2, msg);
  void error(String msg) => _log(3, msg);

  static String _levelTag(int level) {
    switch (level) {
      case 0: return 'DEBUG';
      case 1: return 'INFO';
      case 2: return 'WARN';
      case 3: return 'ERROR';
      default: return 'INFO';
    }
  }
}
