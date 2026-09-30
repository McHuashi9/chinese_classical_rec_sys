import 'dart:collection';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import '../bridge/ffi_bindings.dart';

/// 底层日志写入通道：level 取值 0=DEBUG / 1=INFO / 2=WARN / 3=ERROR。
typedef AppLogSink = void Function(int level, String message);

/// 桥未就绪期内存环形缓冲的容量上限（A2，零 ABI）。
const int kAppLoggerPendingCapacity = 200;

/// 应用日志入口（硬单例）。
///
/// 转发链路：`AppLogger` --FFI `log_write`--> `bridge_log.cpp` --> spdlog。
/// 桥未就绪期（如核心库加载失败）不再直接丢日志：先落内存环形缓冲，
/// 待桥与 C++ 文件 sink 就绪后由 [flushPending] 一次性回放（A2）。
class AppLogger {
  static AppLogger? _instance;
  AppLogger._();
  factory AppLogger() => _instance ??= AppLogger._();

  /// 桥未就绪期的日志缓冲，上限 [kAppLoggerPendingCapacity] 条（环形，超限丢最旧）。
  final ListQueue<(int, String)> _pending = ListQueue<(int, String)>();

  /// 测试注入的写入通道；非 null 时视为「桥已就绪」并绕过 FFI（A7）。
  @visibleForTesting
  AppLogSink? sinkOverride;

  NativeBridge? get _bridge => NativeBridge.instance;

  bool get _channelReady => sinkOverride != null || _bridge != null;

  /// 当前缓冲条数（A2 测试用）。
  @visibleForTesting
  int get pendingCount => _pending.length;

  void _log(int level, String message) {
    // A1：日志自身任何失败都不得外抛（会打断业务调用），
    // 且 `toNativeUtf8` 分配的内存必须释放（见 [_tryDeliver] 的 finally）。
    try {
      if (_tryDeliver(level, message)) return;
      _enqueue(level, message);
      debugPrint('[${_levelTag(level)}] $message');
    } catch (e) {
      debugPrint('[${_levelTag(level)}] (日志写入失败: $e) $message');
    }
  }

  /// 尝试立即写入底层通道。
  ///
  /// 返回 false 表示桥未就绪（调用方转入缓冲）；写入本身抛错则由 `_log` 兜底。
  bool _tryDeliver(int level, String message) {
    final sink = sinkOverride;
    if (sink != null) {
      sink(level, message);
      return true;
    }
    final bridge = _bridge;
    if (bridge == null) return false;

    final ptr = message.toNativeUtf8();
    try {
      bridge.logWrite(level, ptr);
    } finally {
      // A1：无论 logWrite 是否抛错都释放 native 内存。
      calloc.free(ptr);
    }
    return true;
  }

  /// 入环形缓冲；满 [kAppLoggerPendingCapacity] 时丢弃最旧一条。
  void _enqueue(int level, String message) {
    if (_pending.length >= kAppLoggerPendingCapacity) {
      _pending.removeFirst();
    }
    _pending.addLast((level, message));
  }

  /// 回放桥未就绪期缓冲的日志（A2）。
  ///
  /// 调用时机（写在 [main.dart] `_initApp`）：`coord.init` 返回之后——此刻
  /// `db_open` 已执行过 C++ 侧 `Logger::init`，旋转文件 sink 才真正可用；
  /// 若在 `NativeBridge.fromLib` 之后、`db_open` 之前回放，日志只会进
  /// spdlog 的默认 stdout sink，Windows release 仍会丢。
  ///
  /// 桥仍未就绪时保留缓冲等待下一次调用；单条回放失败静默丢弃，绝不影响调用方。
  void flushPending() {
    if (_pending.isEmpty || !_channelReady) return;
    final entries = List<(int, String)>.of(_pending);
    _pending.clear();
    for (final (level, message) in entries) {
      try {
        _tryDeliver(level, message);
      } catch (_) {
        // A2：回放失败静默——日志不是关键路径。
      }
    }
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
