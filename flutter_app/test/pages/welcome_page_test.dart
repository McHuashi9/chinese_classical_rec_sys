import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chinese_classical_rec_sys/engine/profile_repository.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/engine/user_init_repository.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/models/user_profile.dart';
import 'package:chinese_classical_rec_sys/pages/welcome_page.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

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
  final bool initialized;
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

  bool renameCalled = false;
  String? renamedTo;
  bool renameResult = true;

  @override
  bool renameProfile(int id, String name) {
    renameCalled = true;
    renamedTo = name;
    if (!renameResult) return false;
    return userCtrl.renameProfile(id, name);
  }

  @override
  List<ChineseText> getInitTexts() => [];
}

_FakeCoordinator _makeCoordinator({String defaultName = '默认用户'}) {
  final navCtrl = NavigationController();
  final settingsCtrl = SettingsController();
  final readTracker = ReadTracker();
  final readingCtrl = ReadingController(readTracker);
  final userCtrl = UserController();
  final repo = _FakeProfileRepository();
  repo.profiles.add(UserProfile(
      id: 1, name: defaultName, createdAt: 1001, lastUsedAt: 2001));
  userCtrl.initProfiles(repo);
  userCtrl.initUserInitRepository(_FakeUserInitRepository(false));
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

Widget _host(AppCoordinator coord, {VoidCallback? onPopped}) {
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
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const WelcomePage()),
                );
                onPopped?.call();
              },
              child: const Text('打开欢迎页'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('欢迎页展示默认用户名和开始初始化按钮', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final coord = _makeCoordinator();
    await tester.pumpWidget(_host(coord));
    await tester.tap(find.text('打开欢迎页'));
    await tester.pumpAndSettle();

    expect(find.text('欢迎使用文言文推荐系统'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '默认用户');
    expect(find.text('开始初始化'), findsOneWidget);
  });

  testWidgets('输入新名字后点击开始会重命名默认档案并返回', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final coord = _makeCoordinator();
    var popped = false;
    await tester.pumpWidget(_host(coord, onPopped: () => popped = true));
    await tester.tap(find.text('打开欢迎页'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '小明');
    await tester.tap(find.text('开始初始化'));
    await tester.pumpAndSettle();

    expect(coord.renameCalled, isTrue);
    expect(coord.renamedTo, '小明');
    expect(coord.userCtrl.profiles.first.name, '小明');
    expect(popped, isTrue);
  });

  testWidgets('清空输入时保留默认用户并返回', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final coord = _makeCoordinator();
    var popped = false;
    await tester.pumpWidget(_host(coord, onPopped: () => popped = true));
    await tester.tap(find.text('打开欢迎页'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('开始初始化'));
    await tester.pumpAndSettle();

    expect(coord.renameCalled, isFalse);
    expect(coord.userCtrl.profiles.first.name, '默认用户');
    expect(popped, isTrue);
  });

  testWidgets('超长名提示并停留在欢迎页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final coord = _makeCoordinator();
    var popped = false;
    await tester.pumpWidget(_host(coord, onPopped: () => popped = true));
    await tester.tap(find.text('打开欢迎页'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '长' * 22);
    await tester.tap(find.text('开始初始化'));
    await tester.pumpAndSettle();

    expect(find.text('名称过长，请缩短'), findsOneWidget);
    expect(find.byType(WelcomePage), findsOneWidget);
    expect(popped, isFalse);
  });

  testWidgets('重命名失败提示并停留在欢迎页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final coord = _makeCoordinator();
    coord.renameResult = false;
    var popped = false;
    await tester.pumpWidget(_host(coord, onPopped: () => popped = true));
    await tester.tap(find.text('打开欢迎页'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '小明');
    await tester.tap(find.text('开始初始化'));
    await tester.pumpAndSettle();

    expect(coord.renameCalled, isTrue);
    expect(find.text('重命名失败，请检查名称长度'), findsOneWidget);
    expect(find.byType(WelcomePage), findsOneWidget);
    expect(popped, isFalse);
  });
}
