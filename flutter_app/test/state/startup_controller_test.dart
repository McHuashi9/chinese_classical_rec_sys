import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/engine/app_logger.dart';
import 'package:chinese_classical_rec_sys/engine/db_open_error_message.dart';
import 'package:chinese_classical_rec_sys/state/startup_controller.dart';

class FakeStartupDriver implements StartupDriver {
  final List<String> calls = <String>[];

  StartupPrepareResult prepareResult = const StartupPrepareResult.ok();
  Object? prepareError;
  Object? announcementError;
  Object? festivalError;
  @override
  bool shouldShowWelcome = false;
  @override
  bool needsInitGuide = false;
  bool welcomeCompleted = true;
  Completer<void>? welcomeGate;

  @override
  Future<StartupPrepareResult> prepare() async {
    calls.add('prepare');
    final error = prepareError;
    if (error != null) throw error;
    return prepareResult;
  }

  @override
  Future<void> afterDatabaseReady() async {
    calls.add('afterDatabaseReady');
  }

  @override
  Future<void> showAnnouncement() async {
    calls.add('showAnnouncement');
    final error = announcementError;
    if (error != null) throw error;
  }

  @override
  Future<void> showFestival() async {
    calls.add('showFestival');
    final error = festivalError;
    if (error != null) throw error;
  }

  @override
  Future<bool> showWelcome() async {
    calls.add('showWelcome');
    final gate = welcomeGate;
    if (gate != null) await gate.future;
    return welcomeCompleted;
  }

  @override
  Future<void> markWelcomeSeen() async {
    calls.add('markWelcomeSeen');
  }

  @override
  Future<void> showInitGuide() async {
    calls.add('showInitGuide');
  }

  @override
  void postInit() {
    calls.add('postInit');
  }
}

void main() {
  test('正常启动按固定顺序执行并进入 ready', () async {
    final driver = FakeStartupDriver()
      ..shouldShowWelcome = true
      ..needsInitGuide = true
      ..welcomeCompleted = true;
    final controller = StartupController(driver: driver);

    await controller.start();

    expect(driver.calls, <String>[
      'prepare',
      'afterDatabaseReady',
      'showAnnouncement',
      'showFestival',
      'showWelcome',
      'markWelcomeSeen',
      'showInitGuide',
      'postInit',
    ]);
    expect(controller.state.phase, StartupPhase.ready);
    expect(controller.state.errorMessage, isNull);
  });

  test('欢迎页未完成时不写 seen，但仍继续初始化引导', () async {
    final driver = FakeStartupDriver()
      ..shouldShowWelcome = true
      ..needsInitGuide = true
      ..welcomeCompleted = false;
    final controller = StartupController(driver: driver);

    await controller.start();

    expect(driver.calls, isNot(contains('markWelcomeSeen')));
    expect(driver.calls, contains('showInitGuide'));
    expect(controller.state.phase, StartupPhase.ready);
  });

  test('prepare 返回失败：进入 fatal 且不执行后续步骤', () async {
    final driver = FakeStartupDriver()
      ..prepareResult = const StartupPrepareResult.failure('数据库打开失败');
    final controller = StartupController(driver: driver);

    await controller.start();

    expect(driver.calls, <String>['prepare']);
    expect(controller.state.phase, StartupPhase.fatal);
    expect(controller.state.errorMessage, '数据库打开失败');
  });

  test('prepare 抛错：用户态只显示通用文案，原始异常进日志', () async {
    final logs = <String>[];
    AppLogger().sinkOverride = (level, message) => logs.add('$level:$message');
    addTearDown(() => AppLogger().sinkOverride = null);
    final driver = FakeStartupDriver()
      ..prepareError = StateError('ffi load /home/alice/libchinese_core.so');
    final controller = StartupController(driver: driver);

    await controller.start();

    expect(driver.calls, <String>['prepare']);
    expect(controller.state.phase, StartupPhase.fatal);
    expect(controller.state.errorMessage, '启动失败，请重启应用。');
    expect(controller.state.errorMessage, isNot(contains('ffi load')));
    expect(logs.join('\n'), contains('StartupController 启动异常'));
    expect(logs.join('\n'), contains('<appdata>/libchinese_core.so'));
    expect(logs.join('\n'), isNot(contains('/home/alice')));
  });

  test('公告步骤抛错：停止后续步骤并进入 fatal', () async {
    final driver = FakeStartupDriver()..announcementError = StateError('ui');
    final controller = StartupController(driver: driver);

    await controller.start();

    expect(driver.calls,
        <String>['prepare', 'afterDatabaseReady', 'showAnnouncement']);
    expect(controller.state.phase, StartupPhase.fatal);
  });

  test('dispose 后未完成的欢迎流程不再触发后续 UI/状态更新', () async {
    final gate = Completer<void>();
    final driver = FakeStartupDriver()
      ..shouldShowWelcome = true
      ..needsInitGuide = true
      ..welcomeGate = gate;
    final controller = StartupController(driver: driver);
    var notifications = 0;
    controller.addListener(() => notifications++);

    final run = controller.start();
    await Future<void>.delayed(Duration.zero);
    expect(driver.calls, contains('showWelcome'));

    controller.dispose();
    gate.complete();
    await run;

    expect(driver.calls, isNot(contains('markWelcomeSeen')));
    expect(driver.calls, isNot(contains('showInitGuide')));
    expect(driver.calls, isNot(contains('postInit')));
    expect(notifications, lessThanOrEqualTo(2));
  });

  test('DB 错误码映射保持既有文案', () {
    expect(dbOpenErrorMessage(BridgeError.errDbContent), contains('内容库缺失或损坏'));
    expect(dbOpenErrorMessage(BridgeError.errDbUser), contains('用户库缺失或损坏'));
    expect(dbOpenErrorMessage(BridgeError.errDbVersion), contains('版本不兼容'));
    expect(dbOpenErrorMessage(BridgeError.errDbSamePath), contains('路径相同'));
    expect(dbOpenErrorMessage(null), contains('数据库打开失败'));
  });
}
