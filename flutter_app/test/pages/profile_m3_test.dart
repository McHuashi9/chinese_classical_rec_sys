import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chinese_classical_rec_sys/engine/profile_repository.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/models/user_profile.dart';
import 'package:chinese_classical_rec_sys/pages/settings_page.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

class _FakeProfileRepository implements ProfileRepository {
  final List<UserProfile> profiles = [];
  int activeId = 1;

  @override
  List<UserProfile> listProfiles() => List.of(profiles);

  @override
  int activeUserId() => activeId;

  @override
  int? createProfile(String name) {
    final id = profiles.length + 1;
    profiles.add(UserProfile(
        id: id, name: name, createdAt: 1000 + id, lastUsedAt: 2000 + id));
    return id;
  }

  @override
  int? createProfileInherit(String name, int sourceId) {
    final id = profiles.length + 1;
    profiles.add(UserProfile(
        id: id, name: name, createdAt: 1000 + id, lastUsedAt: 2000 + id));
    return id;
  }

  @override
  bool switchProfile(int id) {
    if (!profiles.any((p) => p.id == id)) return false;
    activeId = id;
    return true;
  }

  @override
  bool renameProfile(int id, String name) {
    final idx = profiles.indexWhere((p) => p.id == id);
    if (idx < 0) return false;
    profiles[idx] = UserProfile(
        id: id,
        name: name,
        createdAt: profiles[idx].createdAt,
        lastUsedAt: profiles[idx].lastUsedAt);
    return true;
  }

  @override
  bool deleteProfile(int id) {
    final idx = profiles.indexWhere((p) => p.id == id);
    if (idx < 0) return false;
    profiles.removeAt(idx);
    return true;
  }
}

class _FakeCoordinator extends AppCoordinator {
  _FakeCoordinator({
    required super.navCtrl,
    required super.settingsCtrl,
    required super.readingCtrl,
    required super.userCtrl,
    required super.readTracker,
  });

  @override
  bool switchProfile(int id) {
    return userCtrl.profiles.any((p) => p.id == id);
  }
}

_FakeCoordinator _makeCoordinator() {
  final navCtrl = NavigationController();
  final settingsCtrl = SettingsController();
  final readTracker = ReadTracker();
  final readingCtrl = ReadingController(readTracker);
  final userCtrl = UserController();
  final repo = _FakeProfileRepository();
  final now = DateTime(2026, 8, 16, 21, 36).millisecondsSinceEpoch ~/ 1000;
  repo.profiles.addAll([
    UserProfile(
        id: 1, name: '默认用户', createdAt: now - 1000, lastUsedAt: now - 100),
    UserProfile(id: 2, name: '小明', createdAt: now - 800, lastUsedAt: now),
  ]);
  userCtrl.initProfiles(repo);
  userCtrl.refreshProfiles();
  return _FakeCoordinator(
    navCtrl: navCtrl,
    settingsCtrl: settingsCtrl,
    readingCtrl: readingCtrl,
    userCtrl: userCtrl,
    readTracker: readTracker,
  );
}

Widget _wrap(AppCoordinator coord) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: coord.navCtrl),
      ChangeNotifierProvider.value(value: coord.settingsCtrl),
      ChangeNotifierProvider.value(value: coord.readingCtrl),
      ChangeNotifierProvider.value(value: coord.userCtrl),
      Provider.value(value: coord),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme(ScreenSize.medium, 1.0,
          accentColor: AppTheme.vermilion),
      darkTheme: AppTheme.darkTheme(ScreenSize.medium, 1.0,
          accentColor: AppTheme.vermilion),
      themeMode: ThemeMode.light,
      home: const Scaffold(body: SettingsPage()),
    ),
  );
}

void main() {
  testWidgets('设置页显示最后使用时间', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final coord = _makeCoordinator();
    await tester.pumpWidget(_wrap(coord));
    await tester.pumpAndSettle();

    expect(find.textContaining('最后使用'), findsNWidgets(2));
    expect(find.textContaining('当前使用 · 最后使用'), findsOneWidget);
  });

  testWidgets('切换档案成功后显示 SnackBar', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final coord = _makeCoordinator();
    await tester.pumpWidget(_wrap(coord));
    await tester.pumpAndSettle();

    await tester.tap(find.text('小明'));
    await tester.pumpAndSettle();

    expect(find.text('已切换到「小明」'), findsOneWidget);
  });
}
