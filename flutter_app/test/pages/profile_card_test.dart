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
  final List<UserProfile> profiles = [
    const UserProfile(id: 1, name: '默认用户', createdAt: 1, lastUsedAt: 2),
    const UserProfile(id: 2, name: '小明', createdAt: 3, lastUsedAt: 4),
  ];
  int activeId = 1;
  int nextId = 3;

  @override
  List<UserProfile> listProfiles() => List.of(profiles);

  @override
  int activeUserId() => activeId;

  @override
  int? createProfile(String name) {
    final id = nextId++;
    profiles.add(UserProfile(
        id: id, name: name, createdAt: id, lastUsedAt: id + 10));
    return id;
  }

  @override
  int? createProfileInherit(String name, int sourceId) {
    final id = nextId++;
    profiles.add(UserProfile(
        id: id, name: name, createdAt: id, lastUsedAt: id + 10));
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

Widget _wrap(UserController userCtrl, AppCoordinator coord,
    SettingsController settingsCtrl) {
  final navCtrl = NavigationController();
  final readTracker = ReadTracker();
  final readingCtrl = ReadingController(readTracker);
  return MultiProvider(
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
      themeMode: ThemeMode.light,
      home: const Scaffold(body: SettingsPage()),
    ),
  );
}

void main() {
  testWidgets('设置页展示用户档案列表与当前标记', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final settingsCtrl = SettingsController();
    final userCtrl = UserController()..initProfiles(_FakeProfileRepository());
    userCtrl.refreshProfiles();
    final coord = AppCoordinator(
      navCtrl: NavigationController(),
      settingsCtrl: settingsCtrl,
      readingCtrl: ReadingController(ReadTracker()),
      userCtrl: userCtrl,
      readTracker: ReadTracker(),
    );

    await tester.pumpWidget(_wrap(userCtrl, coord, settingsCtrl));
    await tester.pumpAndSettle();

    expect(find.text('用户档案'), findsOneWidget);
    expect(find.text('默认用户'), findsOneWidget);
    expect(find.text('小明'), findsOneWidget);
    expect(find.textContaining('当前使用'), findsOneWidget);
  });

  testWidgets('新建档案对话框：确认后列表新增档案', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final settingsCtrl = SettingsController();
    final userCtrl = UserController()..initProfiles(_FakeProfileRepository());
    userCtrl.refreshProfiles();
    final coord = AppCoordinator(
      navCtrl: NavigationController(),
      settingsCtrl: settingsCtrl,
      readingCtrl: ReadingController(ReadTracker()),
      userCtrl: userCtrl,
      readTracker: ReadTracker(),
    );

    await tester.pumpWidget(_wrap(userCtrl, coord, settingsCtrl));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新建用户'));
    await tester.pumpAndSettle();
    expect(find.text('新建用户档案'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '小红');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 新档案二选一：选“继承已有档案”可避免进入初始化流程
    expect(find.text('新档案初始化方式'), findsOneWidget);
    await tester.tap(find.text('继承已有档案'));
    await tester.pumpAndSettle();
    expect(find.text('选择要继承的档案'), findsOneWidget);
    await tester.tap(find.text('默认用户').last);
    await tester.pumpAndSettle();

    expect(find.text('小红'), findsOneWidget);
  });
}
