import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/main.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/state/screenshot_controller.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';

void main() {
  testWidgets('App shell builds', (WidgetTester tester) async {
    final navCtrl = NavigationController();
    final settingsCtrl = SettingsController();
    final readTracker = ReadTracker();
    final readingCtrl = ReadingController(readTracker);
    final userCtrl = UserController();
    final screenshotCtrl = ScreenshotController();
    final coord = AppCoordinator(
      navCtrl: navCtrl,
      settingsCtrl: settingsCtrl,
      readingCtrl: readingCtrl,
      userCtrl: userCtrl,
      readTracker: readTracker,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: navCtrl),
          ChangeNotifierProvider.value(value: settingsCtrl),
          ChangeNotifierProvider.value(value: readingCtrl),
          ChangeNotifierProvider.value(value: userCtrl),
          ChangeNotifierProvider.value(value: screenshotCtrl),
          Provider.value(value: coord),
        ],
        child: const ChineseClassicalRecSysApp(),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('armed 时 App 根级显示截图确认浮层', (WidgetTester tester) async {
    final navCtrl = NavigationController();
    final settingsCtrl = SettingsController();
    final readTracker = ReadTracker();
    final readingCtrl = ReadingController(readTracker);
    final userCtrl = UserController();
    final screenshotCtrl = ScreenshotController();
    final coord = AppCoordinator(
      navCtrl: navCtrl,
      settingsCtrl: settingsCtrl,
      readingCtrl: readingCtrl,
      userCtrl: userCtrl,
      readTracker: readTracker,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: navCtrl),
          ChangeNotifierProvider.value(value: settingsCtrl),
          ChangeNotifierProvider.value(value: readingCtrl),
          ChangeNotifierProvider.value(value: userCtrl),
          ChangeNotifierProvider.value(value: screenshotCtrl),
          Provider.value(value: coord),
        ],
        child: const ChineseClassicalRecSysApp(
          screenshotCapture: _fakeCapture,
        ),
      ),
    );

    screenshotCtrl.arm();
    await tester.pump();

    expect(find.text('已开启截图模式，请切换到目标界面'), findsOneWidget);
  });
}

Future<String> _fakeCapture() async => '/tmp/fake_screenshot.png';
