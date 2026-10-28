import 'dart:async';

import 'package:flutter/foundation.dart' show FlutterError, debugPrint;
import 'package:flutter/material.dart' show runApp;
import 'package:provider/provider.dart';

import 'app.dart';
import 'engine/app_logger.dart';
import 'engine/read_tracker.dart';
import 'state/coordinator.dart';
import 'state/navigation_controller.dart';
import 'state/reading_controller.dart';
import 'state/screenshot_controller.dart';
import 'state/settings_controller.dart';
import 'state/user_controller.dart';

/// 未捕获异常的兜底记录：写进 `logs/app.log`，便于事后排查。
///
/// 没有这段兜底时，崩溃可能一行日志都不留，只剩终端红字（关掉终端即失去线索）。
/// 这里只做“记录”，不改控制流。
void _logUncaughtError(String source, Object error, StackTrace? stack) {
  try {
    AppLogger().error('$source: $error${stack == null ? '' : '\n$stack'}');
  } catch (_) {
    // 日志系统本身不可用（如引擎未加载）时退化为控制台输出，绝不二次抛出。
    debugPrint('$source: $error\n$stack');
  }
}

void main() {
  // 框架层异常（build/layout/paint 及 onPressed 等回调抛错）走这里。
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    _logUncaughtError(
        'FlutterError', details.exception, details.stack ?? StackTrace.current);
    previousOnError?.call(details);
  };

  // 异步未捕获异常（Future 未 await、Timer 内抛错等）走这里。
  // 注意：已交由 FlutterError 处理的框架异常不会进这个 zone，二者互补不重复。
  runZonedGuarded(() => _bootstrap(), (error, stack) {
    _logUncaughtError('UncaughtError', error, stack);
  });
}

void _bootstrap() {
  final readTracker = ReadTracker();
  final navCtrl = NavigationController();
  final settingsCtrl = SettingsController();
  final readingCtrl = ReadingController(readTracker);
  final userCtrl = UserController();
  final screenshotCtrl = ScreenshotController();
  final coordinator = AppCoordinator(
    navCtrl: navCtrl,
    settingsCtrl: settingsCtrl,
    readingCtrl: readingCtrl,
    userCtrl: userCtrl,
    readTracker: readTracker,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: navCtrl),
        ChangeNotifierProvider.value(value: settingsCtrl),
        ChangeNotifierProvider.value(value: readingCtrl),
        ChangeNotifierProvider.value(value: userCtrl),
        ChangeNotifierProvider.value(value: screenshotCtrl),
        Provider.value(value: coordinator),
      ],
      child: const ChineseClassicalRecSysApp(),
    ),
  );
}
