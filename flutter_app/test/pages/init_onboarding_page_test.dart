import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/engine/user_init_repository.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/pages/init_onboarding_page.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

class _FakeCoordinator extends AppCoordinator {
  _FakeCoordinator({
    required super.navCtrl,
    required super.settingsCtrl,
    required super.readingCtrl,
    required super.userCtrl,
    required super.readTracker,
  });

  List<ChineseText> initTexts = [];
  String rawAnnotations = '';
  String translation = '';

  @override
  List<ChineseText> getInitTexts() => initTexts;

  @override
  String getAnnotations(int textId) => rawAnnotations;

  @override
  String getTranslation(int textId) => translation;
}

ChineseText _text(int id, String title) => ChineseText(
      id: id,
      title: title,
      author: '作者',
      dynasty: '宋',
      source: '古文观止',
      content: '内容$id',
      charCount: 10,
      difficulties: List.filled(10, 0.5),
    );

void main() {
  late NavigationController navCtrl;
  late SettingsController settingsCtrl;
  late ReadTracker readTracker;
  late ReadingController readingCtrl;
  late UserController userCtrl;
  late _FakeCoordinator coord;

  setUp(() {
    navCtrl = NavigationController();
    settingsCtrl = SettingsController();
    readTracker = ReadTracker();
    readingCtrl = ReadingController(readTracker);
    userCtrl = UserController();
    coord = _FakeCoordinator(
      navCtrl: navCtrl,
      settingsCtrl: settingsCtrl,
      readingCtrl: readingCtrl,
      userCtrl: userCtrl,
      readTracker: readTracker,
    );
  });

  tearDown(() {
    readingCtrl.dispose();
    userCtrl.dispose();
  });

  Widget wrap(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: navCtrl),
        ChangeNotifierProvider.value(value: settingsCtrl),
        ChangeNotifierProvider.value(value: readingCtrl),
        ChangeNotifierProvider<UserController>.value(value: userCtrl),
        Provider<AppCoordinator>.value(value: coord),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(ScreenSize.medium, 1.0,
            accentColor: AppTheme.vermilion),
        darkTheme: AppTheme.darkTheme(ScreenSize.medium, 1.0,
            accentColor: AppTheme.vermilion),
        themeMode: settingsCtrl.darkMode ? ThemeMode.dark : ThemeMode.light,
        home: child,
      ),
    );
  }

  testWidgets('未初始化时展示两篇文章与未就绪按钮', (tester) async {
    coord.initTexts = [_text(41, '严先生祠堂记'), _text(166, '周郑交质')];
    await tester.pumpWidget(wrap(const InitOnboardingPage()));
    await tester.pumpAndSettle();

    expect(find.text('初始化引导'), findsOneWidget);
    expect(find.text('严先生祠堂记'), findsOneWidget);
    expect(find.text('周郑交质'), findsOneWidget);
    expect(find.text('请先阅读两篇文章'), findsOneWidget);
  });

  testWidgets('两篇均已读后按钮变为开始初始化', (tester) async {
    coord.initTexts = [_text(41, '严先生祠堂记'), _text(166, '周郑交质')];
    readTracker.markEffectApplied(41);
    readTracker.markEffectApplied(166);
    await tester.pumpWidget(wrap(const InitOnboardingPage()));
    await tester.pumpAndSettle();

    expect(find.text('开始 6 题初始化'), findsOneWidget);
  });

  testWidgets('已初始化时显示完成态', (tester) async {
    userCtrl.initUserInitRepository(_FakeInitRepo(initialized: true));
    userCtrl.refreshInitState();
    await tester.pumpWidget(wrap(const InitOnboardingPage()));
    await tester.pumpAndSettle();

    expect(find.text('初始化完成'), findsOneWidget);
    expect(find.text('已完成初始化，可以开始学习了'), findsOneWidget);
  });
}

class _FakeInitRepo implements UserInitRepository {
  final bool initialized;
  _FakeInitRepo({required this.initialized});

  @override
  bool isInitialized() => initialized;

  @override
  List<Question> initQuestions() => [];

  @override
  void disposeInitQuestions(List<Question> questions) {}

  @override
  User? applyInit(List<int> qids, List<int> choices) => null;
}
