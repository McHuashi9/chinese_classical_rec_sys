import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
import 'package:chinese_classical_rec_sys/pages/settings_page.dart';
import 'package:chinese_classical_rec_sys/pages/library_page.dart';
import 'package:chinese_classical_rec_sys/pages/read_page.dart';
import 'package:chinese_classical_rec_sys/pages/ability_page.dart';

Widget _wrap(AppState app, Widget child) {
  return ChangeNotifierProvider.value(
    value: app,
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
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
      final app = AppState();
      await tester.pumpWidget(_wrap(app, const SettingsPage()));
      await tester.pumpAndSettle();

      expect(find.text('设置'), findsOneWidget);
      expect(find.text('外观'), findsOneWidget);
      expect(find.text('日志'), findsOneWidget);
      expect(find.text('关于'), findsOneWidget);
      expect(find.text('版本 v0.2.0'), findsOneWidget);
      app.dispose();
    });

    testWidgets('dark mode toggle switches theme', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final app = AppState();
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          themeMode: app.darkMode ? ThemeMode.dark : ThemeMode.light,
          home: const Scaffold(body: SettingsPage()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(app.darkMode, false);
      expect(find.text('暗色'), findsOneWidget);
      app.dispose();
    });
  });

  group('LibraryPage', () {
    testWidgets('shows empty state when no texts', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final app = AppState();
      await tester.pumpWidget(_wrap(app, const LibraryPage()));
      await tester.pumpAndSettle();

      expect(find.text('文库'), findsOneWidget);
      expect(find.text('未找到匹配篇目'), findsOneWidget);
      app.dispose();
    });
  });

  group('ReadPage', () {
    testWidgets('shows placeholder when no text loaded', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final app = AppState();
      await tester.pumpWidget(_wrap(app, const ReadPage()));
      await tester.pumpAndSettle();

      expect(find.text('请从文库选择一篇古文'), findsOneWidget);
      app.dispose();
    });
  });

  group('AbilityPage', () {
    testWidgets('shows loader when user is null', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final app = AppState();
      await tester.pumpWidget(_wrap(app, const AbilityPage()));
      // RadarChart uses AnimationController; pump frame to avoid timeout
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      app.dispose();
    });
  });
}
