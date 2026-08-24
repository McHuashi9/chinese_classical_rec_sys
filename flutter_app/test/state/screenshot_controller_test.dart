import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/state/screenshot_controller.dart';

void main() {
  group('ScreenshotController', () {
    late ScreenshotController ctrl;

    setUp(() => ctrl = ScreenshotController());
    tearDown(() => ctrl.dispose());

    test('初始未开启且无截图', () {
      expect(ctrl.armed, isFalse);
      expect(ctrl.lastPath, isNull);
    });

    test('arm 开启截图模式并清空上次路径', () {
      ctrl.complete('old.png');
      expect(ctrl.lastPath, 'old.png');

      ctrl.arm();
      expect(ctrl.armed, isTrue);
      expect(ctrl.lastPath, isNull);
    });

    test('complete 结束截图模式并记录路径', () {
      ctrl.arm();
      ctrl.complete('/tmp/shot.png');

      expect(ctrl.armed, isFalse);
      expect(ctrl.lastPath, '/tmp/shot.png');
    });

    test('cancel 结束截图模式并清空路径', () {
      ctrl.arm();
      ctrl.complete('/tmp/shot.png');
      ctrl.cancel();

      expect(ctrl.armed, isFalse);
      expect(ctrl.lastPath, isNull);
    });

    test('clearLastPath 只清空路径不影响截图模式', () {
      ctrl.arm();
      ctrl.complete('/tmp/shot.png');
      ctrl.clearLastPath();

      expect(ctrl.armed, isFalse);
      expect(ctrl.lastPath, isNull);
    });

    test('状态变化会通知监听者', () {
      var notified = 0;
      ctrl.addListener(() => notified++);
      ctrl.arm();
      ctrl.complete('/tmp/shot.png');
      ctrl.cancel();
      expect(notified, 3);
    });
  });
}
