import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_classical_rec_sys/service/app_screenshot.dart';
import 'package:chinese_classical_rec_sys/state/screenshot_controller.dart';
import 'package:chinese_classical_rec_sys/widgets/screenshot_overlay.dart';

Widget _harness({
  required ScreenshotController controller,
  required ScreenshotCapture capture,
  required Future<void> Function(String path) onOpenFeedback,
}) {
  final navigatorKey = GlobalKey<NavigatorState>();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  final boundaryKey = GlobalKey();
  return ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      builder: (context, child) => Stack(
        children: [
          RepaintBoundary(
            key: boundaryKey,
            child: child ?? const SizedBox.shrink(),
          ),
          if (controller.armed)
            ScreenshotConfirmOverlay(
              controller: controller,
              boundaryKey: boundaryKey,
              navigatorKey: navigatorKey,
              messengerKey: messengerKey,
              capture: capture,
              onOpenFeedback: onOpenFeedback,
            ),
        ],
      ),
      home: const Scaffold(body: Center(child: Text('目标界面'))),
    ),
  );
}

void main() {
  testWidgets('arm 后出现浮层，取消后消失且无副作用', (tester) async {
    final controller = ScreenshotController();
    addTearDown(controller.dispose);
    String? openedFeedback;
    await tester.pumpWidget(_harness(
      controller: controller,
      capture: () async => '/tmp/shot.png',
      onOpenFeedback: (path) async => openedFeedback = path,
    ));

    expect(find.text('已开启截图模式，请切换到目标界面'), findsNothing);

    controller.arm();
    await tester.pump();
    expect(find.text('已开启截图模式，请切换到目标界面'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(find.text('已开启截图模式，请切换到目标界面'), findsNothing);
    expect(controller.armed, isFalse);
    expect(controller.lastPath, isNull);
    expect(openedFeedback, isNull);
  });

  testWidgets('确认截图调用捕获、保存路径并显示 SnackBar 与附带反馈', (tester) async {
    final controller = ScreenshotController();
    addTearDown(controller.dispose);
    var captureCalled = 0;
    String? openedFeedback;
    await tester.pumpWidget(_harness(
      controller: controller,
      capture: () async {
        captureCalled++;
        return '/tmp/shot_20260824.png';
      },
      onOpenFeedback: (path) async => openedFeedback = path,
    ));

    controller.arm();
    await tester.pump();
    await tester.tap(find.text('确认截图'));
    await tester.pumpAndSettle();

    expect(captureCalled, 1);
    expect(controller.armed, isFalse);
    expect(controller.lastPath, '/tmp/shot_20260824.png');
    expect(
        find.textContaining('截图已保存到 /tmp/shot_20260824.png'), findsOneWidget);
    expect(find.text('附带反馈'), findsOneWidget);

    await tester.tap(find.text('附带反馈'));
    await tester.pump();
    expect(openedFeedback, '/tmp/shot_20260824.png');
  });

  testWidgets('截图失败时保留截图模式并提示错误', (tester) async {
    final controller = ScreenshotController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(
      controller: controller,
      capture: () async => throw StateError('test failure'),
      onOpenFeedback: (path) async {},
    ));

    controller.arm();
    await tester.pump();
    await tester.tap(find.text('确认截图'));
    await tester.pumpAndSettle();

    expect(controller.armed, isTrue);
    expect(find.text('已开启截图模式，请切换到目标界面'), findsOneWidget);
    expect(find.textContaining('截图失败'), findsOneWidget);
  });
}
