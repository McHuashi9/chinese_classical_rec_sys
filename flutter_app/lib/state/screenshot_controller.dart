import 'package:flutter/foundation.dart';

/// 软件内截图的会话状态。
///
/// 只保存本次运行期间的截图标记与最近一次截图路径，不持久化。
class ScreenshotController extends ChangeNotifier {
  bool _armed = false;
  String? _lastPath;

  /// 是否已进入「截图待确认」模式。
  bool get armed => _armed;

  /// 本次会话最近一次成功保存的截图路径。
  String? get lastPath => _lastPath;

  /// 进入截图模式。
  void arm() {
    _armed = true;
    _lastPath = null;
    notifyListeners();
  }

  /// 取消截图模式。
  void cancel() {
    _armed = false;
    _lastPath = null;
    notifyListeners();
  }

  /// 截图成功完成：退出截图模式并记录路径。
  void complete(String path) {
    _armed = false;
    _lastPath = path;
    notifyListeners();
  }

  /// 清除最近一次截图路径（保留截图文件本身）。
  void clearLastPath() {
    _lastPath = null;
    notifyListeners();
  }
}
