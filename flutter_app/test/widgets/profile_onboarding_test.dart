import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chinese_classical_rec_sys/engine/profile_repository.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/engine/user_init_repository.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/models/user_profile.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/widgets/profile_dialogs.dart';

class _FakeProfileRepository implements ProfileRepository {
  final List<UserProfile> profiles = [];
  int activeId = 1;
  int nextId = 2;

  @override
  List<UserProfile> listProfiles() => List.of(profiles);

  @override
  int activeUserId() => activeId;

  @override
  int? createProfile(String name) {
    final id = nextId++;
    profiles.add(UserProfile(
        id: id, name: name, createdAt: 1000 + id, lastUsedAt: 2000 + id));
    return id;
  }

  @override
  int? createProfileInherit(String name, int sourceId) {
    final id = nextId++;
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

class _FakeUserInitRepository implements UserInitRepository {
  bool initialized;

  _FakeUserInitRepository(this.initialized);

  @override
  bool isInitialized() => initialized;

  @override
  List<Question> initQuestions() => [];

  @override
  void disposeInitQuestions(List<Question> questions) {}

  @override
  User? applyInit(List<int> qids, List<int> choices) => null;
}

class _FakeCoordinator extends AppCoordinator {
  _FakeCoordinator({
    required super.navCtrl,
    required super.settingsCtrl,
    required super.readingCtrl,
    required super.userCtrl,
    required super.readTracker,
  });

  bool createCalled = false;
  bool inheritCalled = false;
  bool renameCalled = false;
  bool switchCalled = false;
  int? switchedTo;

  @override
  int? createProfile(String name) {
    createCalled = true;
    return userCtrl.createProfile(name);
  }

  @override
  int? createInheritedProfile(String name, int sourceId) {
    inheritCalled = true;
    return userCtrl.createInheritedProfile(name, sourceId);
  }

  @override
  bool renameProfile(int id, String name) {
    renameCalled = true;
    return userCtrl.renameProfile(id, name);
  }

  @override
  bool switchProfile(int id) {
    switchCalled = true;
    switchedTo = id;
    return true;
  }
}

_FakeCoordinator _makeCoordinator({
  bool initialized = false,
  List<UserProfile>? profiles,
}) {
  final navCtrl = NavigationController();
  final settingsCtrl = SettingsController();
  final readTracker = ReadTracker();
  final readingCtrl = ReadingController(readTracker);
  final userCtrl = UserController();
  final repo = _FakeProfileRepository();
  repo.profiles.addAll(profiles ??
      [
        const UserProfile(
            id: 1, name: '默认用户', createdAt: 1001, lastUsedAt: 2001),
      ]);
  userCtrl.initProfiles(repo);
  userCtrl.initUserInitRepository(_FakeUserInitRepository(initialized));
  userCtrl.refreshProfiles();
  userCtrl.refreshInitState();
  return _FakeCoordinator(
    navCtrl: navCtrl,
    settingsCtrl: settingsCtrl,
    readingCtrl: readingCtrl,
    userCtrl: userCtrl,
    readTracker: readTracker,
  );
}

Widget _host(AppCoordinator coord) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: coord.navCtrl),
      ChangeNotifierProvider.value(value: coord.settingsCtrl),
      ChangeNotifierProvider.value(value: coord.readingCtrl),
      ChangeNotifierProvider.value(value: coord.userCtrl),
      Provider.value(value: coord),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => runProfileOnboarding(context, coord),
              child: const Text('开始引导'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('shouldShowProfileOnboarding / markProfileOnboardingSeen', () {
    const profile =
        UserProfile(id: 1, name: '默认用户', createdAt: 1001, lastUsedAt: 2001);

    test('无标记且只有 1 个档案时展示', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(shouldShowProfileOnboarding(prefs, const [profile]), isTrue);
    });

    test('已有标记时不展示', () async {
      SharedPreferences.setMockInitialValues({kProfileOnboardedKey: true});
      final prefs = await SharedPreferences.getInstance();
      expect(shouldShowProfileOnboarding(prefs, const [profile]), isFalse);
    });

    test('无标记但已有多个档案时不展示', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(
        shouldShowProfileOnboarding(prefs, const [
          profile,
          UserProfile(id: 2, name: '小明', createdAt: 1002, lastUsedAt: 2002),
        ]),
        isFalse,
      );
    });

    test('markProfileOnboardingSeen 写入标记', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await markProfileOnboardingSeen(prefs);
      expect(prefs.containsKey(kProfileOnboardedKey), isTrue);
      expect(prefs.getBool(kProfileOnboardedKey), isTrue);
    });
  });

  group('showProfileOnboardingDialog', () {
    testWidgets('展示三个选项与跳过按钮', (tester) async {
      final coord = _makeCoordinator();
      await tester.pumpWidget(_host(coord));
      await tester.tap(find.text('开始引导'));
      await tester.pumpAndSettle();

      expect(find.text('管理学习档案'), findsOneWidget);
      expect(find.text('使用默认用户'), findsOneWidget);
      expect(find.text('新建档案'), findsOneWidget);
      expect(find.text('重命名默认用户'), findsOneWidget);
      expect(find.text('跳过'), findsOneWidget);
    });

    testWidgets('点击跳过返回 skip', (tester) async {
      ProfileOnboardingChoice? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showProfileOnboardingDialog(context);
                },
                child: const Text('开始'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();
      expect(result, ProfileOnboardingChoice.skip);
    });
  });

  group('runProfileOnboarding 流程', () {
    testWidgets('选择“使用默认用户”不产生档案操作', (tester) async {
      final coord = _makeCoordinator();
      await tester.pumpWidget(_host(coord));
      await tester.tap(find.text('开始引导'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用默认用户'));
      await tester.pumpAndSettle();

      expect(coord.createCalled, isFalse);
      expect(coord.inheritCalled, isFalse);
      expect(coord.renameCalled, isFalse);
      expect(coord.switchCalled, isFalse);
      expect(coord.userCtrl.profiles.length, 1);
    });

    testWidgets('选择“跳过”不产生档案操作', (tester) async {
      final coord = _makeCoordinator();
      await tester.pumpWidget(_host(coord));
      await tester.tap(find.text('开始引导'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();

      expect(coord.createCalled, isFalse);
      expect(coord.inheritCalled, isFalse);
      expect(coord.renameCalled, isFalse);
      expect(coord.switchCalled, isFalse);
    });

    testWidgets('默认未初始化时新建档案：创建并切换', (tester) async {
      final coord = _makeCoordinator(initialized: false);
      await tester.pumpWidget(_host(coord));
      await tester.tap(find.text('开始引导'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建档案'));
      await tester.pumpAndSettle();

      expect(find.text('新建用户档案'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '小明');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(coord.createCalled, isTrue);
      expect(coord.inheritCalled, isFalse);
      expect(coord.switchCalled, isTrue);
      expect(coord.switchedTo, 2);
      expect(coord.userCtrl.profiles.map((p) => p.name), contains('小明'));
    });

    testWidgets('默认已初始化时新建档案：选择“完成初始化”', (tester) async {
      final coord = _makeCoordinator(initialized: true);
      await tester.pumpWidget(_host(coord));
      await tester.tap(find.text('开始引导'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建档案'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '小红');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(find.text('新档案初始化方式'), findsOneWidget);
      await tester.tap(find.text('完成初始化'));
      await tester.pumpAndSettle();

      expect(coord.createCalled, isTrue);
      expect(coord.inheritCalled, isFalse);
      expect(coord.switchCalled, isTrue);
      expect(coord.switchedTo, 2);
      expect(coord.userCtrl.profiles.map((p) => p.name), contains('小红'));
    });

    testWidgets('默认已初始化时新建档案：选择“继承已有档案”', (tester) async {
      final coord = _makeCoordinator(initialized: true);
      await tester.pumpWidget(_host(coord));
      await tester.tap(find.text('开始引导'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建档案'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '小刚');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(find.text('新档案初始化方式'), findsOneWidget);
      await tester.tap(find.text('继承已有档案'));
      await tester.pumpAndSettle();

      expect(coord.createCalled, isFalse);
      expect(coord.inheritCalled, isTrue);
      expect(coord.switchCalled, isTrue);
      expect(coord.switchedTo, 2);
      expect(coord.userCtrl.profiles.map((p) => p.name), contains('小刚'));
    });

    testWidgets('重命名默认用户', (tester) async {
      final coord = _makeCoordinator();
      await tester.pumpWidget(_host(coord));
      await tester.tap(find.text('开始引导'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名默认用户'));
      await tester.pumpAndSettle();

      expect(find.text('重命名默认用户'), findsOneWidget); // 当前为命名对话框标题
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, '默认用户');
      await tester.enterText(find.byType(TextField), '我');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(coord.renameCalled, isTrue);
      expect(coord.userCtrl.profiles.first.name, '我');
      expect(coord.switchCalled, isFalse);
    });

    testWidgets('新建档案时取消命名不创建', (tester) async {
      final coord = _makeCoordinator();
      await tester.pumpWidget(_host(coord));
      await tester.tap(find.text('开始引导'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建档案'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(coord.createCalled, isFalse);
      expect(coord.switchCalled, isFalse);
      expect(coord.userCtrl.profiles.length, 1);
    });
  });
}
