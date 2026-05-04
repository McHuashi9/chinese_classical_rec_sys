import 'package:ffi/ffi.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';

/// 知识追踪 FFI 封装
class KnowledgeTracker {
  final NativeBridge _bridge;

  KnowledgeTracker(this._bridge);

  /// 记录阅读事件，更新用户能力
  /// [readTime] 阅读时长(秒)，>=30s 才会触发更新
  /// 返回更新后的用户或 null (读取时间不足)
  User? applyRead(User user, int textId, double readTime) {
    if (readTime < 30) return null;

    final outUser = User.allocate(calloc);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rc = _bridge.trackerApplyRead(
        user.ptr, textId, readTime, now, outUser.ptr);
    if (rc != BridgeError.ok) {
      outUser.dispose();
      return null;
    }
    return outUser;
  }

  /// 应用遗忘效应到当前时刻
  User applyForgetting(User user) {
    final outUser = User.allocate(calloc);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _bridge.trackerApplyForgetting(user.ptr, now, outUser.ptr);
    return outUser;
  }

  /// 清理过期增量，返回更新后的用户
  User prune(User user) {
    final outUser = User.allocate(calloc);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _bridge.trackerPrune(user.ptr, now, outUser.ptr);
    return outUser;
  }
}
