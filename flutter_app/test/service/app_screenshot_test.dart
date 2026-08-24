import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_classical_rec_sys/service/app_screenshot.dart';

void main() {
  group('screenshotFileName', () {
    test('生成带毫秒的固定文件名', () {
      final name = screenshotFileName(DateTime(2026, 8, 24, 9, 5, 7, 123));
      expect(name, 'screenshot_20260824_090507_123.png');
    });

    test('月日时分秒补零', () {
      final name = screenshotFileName(DateTime(2026, 1, 2, 3, 4, 5, 6));
      expect(name, 'screenshot_20260102_030405_006.png');
    });
  });

  group('ensureScreenshotDirectory', () {
    test('自动创建 screenshots 子目录', () async {
      final temp = await Directory.systemTemp.createTemp('app_screenshot_test');
      addTearDown(() => temp.delete(recursive: true));

      final dir = await ensureScreenshotDirectory(outputDir: temp.path);

      expect(dir.path, endsWith('screenshots'));
      expect(await dir.exists(), isTrue);
    });
  });

  testWidgets('边界未就绪时截图服务抛错', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(const SizedBox());
    final expectation = expectLater(
      captureAppScreenshot(key),
      throwsStateError,
    );
    await tester.pump();
    await expectation;
  });
}
