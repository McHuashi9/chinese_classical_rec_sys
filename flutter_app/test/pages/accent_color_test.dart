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
}
