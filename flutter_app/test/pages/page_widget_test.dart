import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/pages/settings_page.dart';
import 'package:chinese_classical_rec_sys/pages/my_page.dart';
import 'package:chinese_classical_rec_sys/pages/read_hub_page.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

Widget _wrap(Widget child) {
  final navCtrl = NavigationController();
  final settingsCtrl = SettingsController();
  final readTracker = ReadTracker();
  final readingCtrl = ReadingController(readTracker);
  final userCtrl = UserController();
  final coord = AppCoordinator(
    navCtrl: navCtrl,
    settingsCtrl: settingsCtrl,
    readingCtrl: readingCtrl,
    userCtrl: userCtrl,
    readTracker: readTracker,
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: navCtrl),
      ChangeNotifierProvider.value(value: settingsCtrl),
      ChangeNotifierProvider.value(value: readingCtrl),
      ChangeNotifierProvider.value(value: userCtrl),
      Provider.value(value: coord),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('SettingsPage', () {
    testWidgets('renders appearance and about cards', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(_wrap(const SettingsPage()));
      await tester.pumpAndSettle();

      expect(find.text('设置'), findsOneWidget);
      expect(find.text('外观'), findsOneWidget);
      expect(find.text('日志'), findsOneWidget);
      expect(find.text('关于'), findsOneWidget);
      expect(find.text('v${AppCoordinator.currentVersion}'), findsOneWidget);
    });

    testWidgets('dark mode toggle switches theme', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final settingsCtrl = SettingsController();
      final navCtrl = NavigationController();
      final readTracker = ReadTracker();
      final readingCtrl = ReadingController(readTracker);
      final userCtrl = UserController();
      final coord = AppCoordinator(
        navCtrl: navCtrl,
        settingsCtrl: settingsCtrl,
        readingCtrl: readingCtrl,
        userCtrl: userCtrl,
        readTracker: readTracker,
      );
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: settingsCtrl,
          builder: (context, _) => MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: navCtrl),
              ChangeNotifierProvider.value(value: settingsCtrl),
              ChangeNotifierProvider.value(value: readingCtrl),
              ChangeNotifierProvider.value(value: userCtrl),
              Provider.value(value: coord),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme(ScreenSize.medium, 1.0,
                  accentColor: AppTheme.vermilion),
              darkTheme: AppTheme.darkTheme(ScreenSize.medium, 1.0,
                  accentColor: AppTheme.vermilion),
              themeMode:
                  settingsCtrl.darkMode ? ThemeMode.dark : ThemeMode.light,
              home: const Scaffold(body: SettingsPage()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(settingsCtrl.darkMode, false);
      expect(
        Theme.of(tester.element(find.text('设置'))).brightness,
        Brightness.light,
      );

      await tester.tap(find.text('暗色模式'));
      await tester.pumpAndSettle();

      expect(settingsCtrl.darkMode, true);
      expect(
        Theme.of(tester.element(find.text('设置'))).brightness,
        Brightness.dark,
      );
    });
  });

  group('ReadHubPage', () {
    testWidgets('shows library tab by default', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(_wrap(const ReadHubPage()));
      await tester.pumpAndSettle();

      expect(find.text('文库'), findsOneWidget);
    });
  });

  group('MyPage', () {
    testWidgets('shows loader when user is null', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(_wrap(const MyPage()));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
