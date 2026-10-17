import 'package:flutter/foundation.dart';

import 'package:chinese_classical_rec_sys/bridge/c_types.dart';

/// 启动主链阶段。UI 只据此渲染加载/错误/主壳，不自行编排业务步骤。
enum StartupPhase {
  loading,
  initializing,
  needsWelcome,
  needsOnboarding,
  ready,
  fatal
}

class StartupState {
  const StartupState({required this.phase, this.errorMessage});

  const StartupState.loading()
      : phase = StartupPhase.loading,
        errorMessage = null;

  final StartupPhase phase;
  final String? errorMessage;

  bool get isReady => phase == StartupPhase.ready;
  bool get isFatal => phase == StartupPhase.fatal;
}

/// `prepare()` 的结果：失败时只带用户可见错误文案，不携带原始异常细节。
class StartupPrepareResult {
  const StartupPrepareResult.ok()
      : ok = true,
        errorMessage = null;

  const StartupPrepareResult.failure(String this.errorMessage) : ok = false;

  final bool ok;
  final String? errorMessage;
}

/// 启动编排所需的副作用边界。
///
/// 生产实现负责与 Flutter 的 `BuildContext`/Navigator/SharedPreferences/DB 交互；
/// [StartupController] 只负责顺序、状态和 disposed/mounted 保护，因此可直接用 fake
/// driver 做单元测试，不启动真实引擎或 UI。
abstract interface class StartupDriver {
  /// 加载 prefs/库、准备 DB、初始化 AppCoordinator、回放启动日志。
  Future<StartupPrepareResult> prepare();

  /// DB 就绪后的状态接线：通知/内容路径/版本/远程同步/档案/推荐/设置。
  Future<void> afterDatabaseReady();

  /// prepare 期间在 activateSavedProfile 之前算出的欢迎页判定。
  bool get shouldShowWelcome;

  /// 欢迎/初始化结束后实时查询当前档案是否仍需强制初始化。
  bool get needsInitGuide;

  Future<void> showAnnouncement();

  Future<void> showFestival();

  /// 返回 true 表示欢迎流程完成，需要写 seen 标记。
  Future<bool> showWelcome();

  Future<void> markWelcomeSeen();

  /// 循环展示强制初始化引导，直到档案初始化完成或页面销毁。
  Future<void> showInitGuide();

  /// 启动完成后的静默更新/同步；允许 fire-and-forget。
  void postInit();
}

/// 启动流程状态机。
///
/// 顺序固定为：prepare → afterDatabaseReady → 公告 → 节日 → 欢迎 → 初始化引导
/// → postInit → ready。任一步抛错进入 fatal；dispose 后不再触发 UI 或通知。
class StartupController extends ChangeNotifier {
  StartupController({required this.driver});

  final StartupDriver driver;

  StartupState _state = const StartupState.loading();
  bool _started = false;
  bool _disposed = false;

  StartupState get state => _state;

  bool get disposed => _disposed;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _setState(const StartupState(phase: StartupPhase.initializing));

    try {
      final prepared = await driver.prepare();
      if (_disposed) return;
      if (!prepared.ok) {
        _fail(prepared.errorMessage ?? '启动失败，请重启应用。');
        return;
      }

      await driver.afterDatabaseReady();
      if (_disposed) return;

      await driver.showAnnouncement();
      if (_disposed) return;

      await driver.showFestival();
      if (_disposed) return;

      if (driver.shouldShowWelcome) {
        _setState(const StartupState(phase: StartupPhase.needsWelcome));
        final completed = await driver.showWelcome();
        if (_disposed) return;
        if (completed) {
          await driver.markWelcomeSeen();
          if (_disposed) return;
        }
      }

      if (driver.needsInitGuide) {
        _setState(const StartupState(phase: StartupPhase.needsOnboarding));
        await driver.showInitGuide();
        if (_disposed) return;
      }

      driver.postInit();
      _setState(const StartupState(phase: StartupPhase.ready));
    } catch (e) {
      if (_disposed) return;
      _fail('启动失败，请重启应用。\n$e');
    }
  }

  void _fail(String message) {
    _setState(StartupState(phase: StartupPhase.fatal, errorMessage: message));
  }

  void _setState(StartupState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// DB 打开失败码 → 用户可见文案。启动编排与 UI 共用这一处映射。
String dbOpenErrorMessage(int? code) {
  switch (code) {
    case BridgeError.errDbContent:
      return '内容库缺失或损坏，请重启应用。\n若持续出现，请重新安装。';
    case BridgeError.errDbUser:
      return '用户库缺失或损坏，请重启应用。\n若持续出现，请重新安装。';
    case BridgeError.errDbVersion:
      return '数据库版本不兼容，请更新应用或重新安装。';
    case BridgeError.errDbSamePath:
      return '内容库与用户库路径相同，请重启应用。';
    default:
      return '数据库打开失败，请重启应用。\n若持续出现，请重新安装。';
  }
}
