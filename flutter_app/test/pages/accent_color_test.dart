import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/pages/settings_page.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/state/screenshot_controller.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

Widget _wrap(SettingsController ctrl) {
  final navCtrl = NavigationController();
  final readTracker = ReadTracker();
  final readingCtrl = ReadingController(readTracker);
  final userCtrl = UserController();
  final coord = AppCoordinator(
    navCtrl: navCtrl,
    settingsCtrl: ctrl,
    readingCtrl: readingCtrl,
    userCtrl: userCtrl,
    readTracker: readTracker,
  );
  return ListenableBuilder(
    listenable: ctrl,
    builder: (context, _) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ctrl),
        ChangeNotifierProvider.value(value: navCtrl),
        ChangeNotifierProvider.value(value: readingCtrl),
        ChangeNotifierProvider.value(value: userCtrl),
        ChangeNotifierProvider.value(value: ScreenshotController()),
        Provider.value(value: coord),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(ScreenSize.medium, 1.0,
            accentColor: AppTheme.vermilion),
        darkTheme: AppTheme.darkTheme(ScreenSize.medium, 1.0,
            accentColor: AppTheme.vermilion),
        themeMode: ctrl.darkMode ? ThemeMode.dark : ThemeMode.light,
        home: const Scaffold(body: SettingsPage()),
      ),
    ),
  );
}

void main() {
  testWidgets('外观卡片渲染主题色区块：12 预设 + 自定义入口', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final ctrl = SettingsController();
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(_wrap(ctrl));
    await tester.pumpAndSettle();

    expect(find.text('主题色'), findsOneWidget);
    expect(find.byKey(const ValueKey('accent-custom')), findsOneWidget);
    for (final color in const [
      Color(0xFFB33A3A),
      Color(0xFF5B7B4A),
      Color(0xFF3A6B8C),
      Color(0xFF8B5E3C),
      Color(0xFF6B4E71),
      Color(0xFF4A7B6B),
      Color(0xFF3A4E6B),
      Color(0xFF7B3A55),
      Color(0xFFA87E2B),
      Color(0xFF4E7B5B),
      Color(0xFF2F4B66),
      Color(0xFF9C3A55),
    ]) {
      expect(find.byKey(ValueKey('accent-preset-${color.toARGB32()}')),
          findsOneWidget);
    }
  });

  testWidgets('点击预设色更新 controller 并成为选中态', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final ctrl = SettingsController();
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(_wrap(ctrl));
    await tester.pumpAndSettle();

    const target = Color(0xFF3A6B8C);
    await tester
        .tap(find.byKey(ValueKey('accent-preset-${target.toARGB32()}')));
    await tester.pumpAndSettle();

    expect(ctrl.accentColorValue, target.toARGB32());
    // 选中态：色块内出现对勾
    expect(
      find.descendant(
          of: find.byKey(ValueKey('accent-preset-${target.toARGB32()}')),
          matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
  });

  testWidgets('自定义取色对话框可打开并取消', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final ctrl = SettingsController();
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(_wrap(ctrl));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('accent-custom')));
    await tester.pumpAndSettle();

    expect(find.text('自定义主题色'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('自定义主题色'), findsNothing);
    expect(ctrl.accentColorValue, AppTheme.vermilion.toARGB32());
  });

  testWidgets('自定义取色确认：颜色被应用并持久化到 controller', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final ctrl = SettingsController();
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(_wrap(ctrl));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('accent-custom')));
    await tester.pumpAndSettle();

    // 在取色器 HSV 区域拖动 → onColorChanged → picked 更新
    final area = find.byKey(const ValueKey('custom-hsv-area'));
    expect(area, findsOneWidget);
    await tester.drag(area, const Offset(60, -80));
    await tester.pumpAndSettle();

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 颜色已被取色器改动并应用（具体色值由拖动位置决定，只断言已变更）
    expect(ctrl.accentColorValue, isNot(AppTheme.vermilion.toARGB32()));
  });

  group('自定义取色对话框：自绘 RGB 滑杆', () {
    Future<void> openDialog(WidgetTester tester, SettingsController ctrl) async {
      await tester.pumpWidget(_wrap(ctrl));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('accent-custom')));
      await tester.pumpAndSettle();
      expect(find.text('自定义主题色'), findsOneWidget);
    }

    int channelOf(WidgetTester tester, String id) => int.parse(
        tester
            .widget<Text>(find.byKey(ValueKey('accent-rgb-$id-value')))
            .data!);

    testWidgets('三条 RGB 滑杆与 0–255 数值文本都在（含 Hue 共 4 条）', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final ctrl = SettingsController();
      addTearDown(ctrl.dispose);

      await openDialog(tester, ctrl);

      // Hue 1 条 + R/G/B 3 条
      expect(find.byType(Slider), findsNWidgets(4));
      for (final id in const ['r', 'g', 'b']) {
        expect(find.byKey(ValueKey('accent-rgb-$id')), findsOneWidget);
      }
      const base = AppTheme.vermilion;
      expect(channelOf(tester, 'r'), (base.r * 255).round());
      expect(channelOf(tester, 'g'), (base.g * 255).round());
      expect(channelOf(tester, 'b'), (base.b * 255).round());
    });

    testWidgets('拖 R 滑杆 → 数值变化，确定后仅红色通道被应用', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final ctrl = SettingsController();
      addTearDown(ctrl.dispose);

      await openDialog(tester, ctrl);

      const base = AppTheme.vermilion;
      final before = channelOf(tester, 'r');
      expect(before, (base.r * 255).round());

      await tester.drag(
          find.byKey(const ValueKey('accent-rgb-r')), const Offset(-40, 0));
      await tester.pumpAndSettle();

      final after = channelOf(tester, 'r');
      expect(after, isNot(before), reason: '拖动 R 滑杆应更新数值文本');

      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      final applied = Color(ctrl.accentColorValue);
      expect((applied.r * 255).round(), after);
      // G/B 通道不被 R 滑杆拖动影响
      expect((applied.g * 255).round(), (base.g * 255).round());
      expect((applied.b * 255).round(), (base.b * 255).round());
    });

    testWidgets('自绘 SV 色盘：顶近白 / 顶右纯色相 / 底黑（multiply 结构正确）', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final ctrl = SettingsController();
      addTearDown(ctrl.dispose);

      await openDialog(tester, ctrl);

      // 直接取色盘内的 CustomPaint 画笔离屏渲染：无 golden 用例时唯一能验证
      // 自绘画笔结构（垂直白→黑 + multiply 水平白→色相）的客观手段。
      // toImage/toByteData 必须在真实异步区里跑（fake async 下会挂起）。
      final customPaint = tester.widget<CustomPaint>(find.descendant(
        of: find.byKey(const ValueKey('custom-hsv-area')),
        matching: find.byType(CustomPaint),
      ));
      List<int> topLeft = const [];
      List<int> topRight = const [];
      List<int> bottom = const [];
      await tester.runAsync(() async {
        const size = Size(100, 100);
        final recorder = ui.PictureRecorder();
        customPaint.painter!.paint(ui.Canvas(recorder), size);
        final image = await recorder.endRecording().toImage(100, 100);
        final data =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        List<int> pixelAt(int x, int y) {
          final offset = (y * 100 + x) * 4;
          return [
            data.getUint8(offset),
            data.getUint8(offset + 1),
            data.getUint8(offset + 2),
          ];
        }

        topLeft = pixelAt(2, 2);
        topRight = pixelAt(97, 2);
        bottom = pixelAt(2, 98);
      });

      // 初始色为朱砂（hue=0）：顶行近白、右上≈纯红、底行≈黑
      expect(topLeft.every((c) => c >= 240), isTrue,
          reason: '顶左应近白，实际 $topLeft');
      expect(topRight[0] >= 240 && topRight[1] <= 20 && topRight[2] <= 20, isTrue,
          reason: '顶右应为纯色相（红），实际 $topRight');
      expect(bottom.every((c) => c <= 15), isTrue,
          reason: '底行应近黑，实际 $bottom');
    });
  });
}
