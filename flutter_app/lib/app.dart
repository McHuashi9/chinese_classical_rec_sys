import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/coordinator.dart';
import 'state/settings_controller.dart';
import 'state/screenshot_controller.dart';
import 'service/app_screenshot.dart';
import 'theme/theme.dart';
import 'pages/main_shell.dart';
import 'widgets/feedback_dialog.dart';
import 'widgets/screenshot_overlay.dart';

class ChineseClassicalRecSysApp extends StatefulWidget {
  const ChineseClassicalRecSysApp({super.key, this.screenshotCapture});

  /// 可注入的截图捕获函数，仅用于测试；生产为 null 使用默认实现。
  final ScreenshotCapture? screenshotCapture;

  @override
  State<ChineseClassicalRecSysApp> createState() =>
      _ChineseClassicalRecSysAppState();
}

class _ChineseClassicalRecSysAppState extends State<ChineseClassicalRecSysApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final GlobalKey _screenshotBoundaryKey = GlobalKey();

  Future<void> _openFeedbackWithScreenshot(String path) async {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    final coord = context.read<AppCoordinator>();
    final schema = coord.schemaVersions;
    final schemaText =
        schema == null ? '不可用' : '用户 ${schema.$1} · 内容 ${schema.$2}';
    await showFeedbackDialog(
      context,
      appVersion: AppCoordinator.currentVersion,
      platform: defaultTargetPlatform.name,
      contentDataVersion: coord.contentDataVersion,
      schemaVersions: schemaText,
      initialScreenshotPath: path,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenshotCtrl = context.watch<ScreenshotController>();
    return LayoutBuilder(builder: (context, constraints) {
      final screenSize = AppTheme.screenSizeForWidth(constraints.maxWidth);
      final isDark = context.select((SettingsController s) => s.darkMode);
      final fontScale = context.select((SettingsController s) => s.fontScale);
      final accent =
          Color(context.select((SettingsController s) => s.accentColorValue));

      return MaterialApp(
        title: '文言文推荐系统',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigatorKey,
        scaffoldMessengerKey: _messengerKey,
        theme: AppTheme.lightTheme(screenSize, fontScale, accentColor: accent),
        darkTheme:
            AppTheme.darkTheme(screenSize, fontScale, accentColor: accent),
        themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        home: const MainShell(),
        builder: (context, child) {
          return Stack(
            children: [
              RepaintBoundary(
                key: _screenshotBoundaryKey,
                child: child ?? const SizedBox.shrink(),
              ),
              if (screenshotCtrl.armed)
                ScreenshotConfirmOverlay(
                  controller: screenshotCtrl,
                  boundaryKey: _screenshotBoundaryKey,
                  navigatorKey: _navigatorKey,
                  messengerKey: _messengerKey,
                  capture: widget.screenshotCapture,
                  onOpenFeedback: _openFeedbackWithScreenshot,
                ),
            ],
          );
        },
      );
    });
  }
}
