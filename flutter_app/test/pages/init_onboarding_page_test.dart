import 'dart:convert';
import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
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
import 'package:chinese_classical_rec_sys/widgets/init_quiz_guide_overlay.dart';

class _FakeCoordinator extends AppCoordinator {
  _FakeCoordinator({
    required super.navCtrl,
    required super.settingsCtrl,
    required super.readingCtrl,
    required super.userCtrl,
    required super.readTracker,
  });

  List<ChineseText> initTexts = [];
  ChineseText? detailOverride;
  String rawAnnotations = '';
  String translation = '';

  @override
  List<ChineseText> getInitTexts() => initTexts;

  @override
  ChineseText? getTextDetail(int textId) => detailOverride;

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

void _writeStr(Array<Uint8> arr, String s, {int offset = 0}) {
  final bytes = utf8.encode(s);
  for (int i = 0; i < bytes.length && i < 512; i++) {
    arr[offset + i] = bytes[i];
  }
  arr[offset + bytes.length] = 0;
}

List<Question> _fakeInitQuestions() {
  final block = calloc<QuestionData>(6);
  for (int i = 0; i < 6; i++) {
    final q = (block + i).ref;
    q.id = 100 + i;
    q.textId = i < 3 ? 41 : 166;
    _writeStr(q.qType, 'shici');
    _writeStr(q.stem, '初始化题${i + 1}');
    for (int k = 0; k < 4; k++) {
      _writeStr(q.options, '选项${k + 1}', offset: k * 512);
    }
    _writeStr(q.dims, '3,4,9');
    _writeStr(q.explanation, '解析${i + 1}');
    q.difficulty = 0.5;
  }
  return [
    for (int i = 0; i < 6; i++) Question(block + i, owner: block),
  ];
}

class _NoopTracker implements QuizTracker {
  @override
  User? applyRead(User user, int textId, double readTime) => null;

  @override
  (User?, bool?) applyQuiz(User user, int questionId, int choice,
      {bool isReview = false}) =>
      (null, null);

  @override
  void disposeQuestions(List<Question> questions) {}

  @override
  QuizBatch getQuestionsForText(int textId) => QuizBatch([]);

  @override
  List<ReviewItem> getDueReviews(int textId) => [];

  @override
  int getDueReviewCount(int textId) => 0;

  @override
  int getTotalReviewCount(int textId) => 0;

  @override
  List<Question> getQuestionsByIds(List<int> ids) => [];

  @override
  QuizAttemptSummary? getAttemptSummary(int textId) => null;

  @override
  User? prune(User user) => null;
}

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

  testWidgets('点击阅读会加载正文详情，不显示暂无内容', (tester) async {
    // 生产路径 getInitTexts() 返回列表缓存（无正文），正文需要 getTextDetail() 拉取。
    coord.initTexts = [
      ChineseText(
        id: 41,
        title: '严先生祠堂记',
        author: '',
        dynasty: '宋',
        source: '古文观止',
        content: '',
        charCount: 0,
        difficulties: List.filled(10, 0.5),
      ),
    ];
    coord.detailOverride = _text(41, '严先生祠堂记');
    await tester.pumpWidget(wrap(const InitOnboardingPage()));
    await tester.tap(find.text('阅读'));
    await tester.pumpAndSettle();

    expect(find.text('暂无内容'), findsNothing);
    // 初始化阅读页与正常阅读页一致：无 AppBar 返回按钮、标题只出现一次（在 ReadingFrame 内）
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.text('严先生祠堂记'), findsOneWidget);
  });

  testWidgets('两篇均已读后按钮提示完成题目', (tester) async {
    coord.initTexts = [_text(41, '严先生祠堂记'), _text(166, '周郑交质')];
    readTracker.markEffectApplied(41);
    readTracker.markEffectApplied(166);
    await tester.pumpWidget(wrap(const InitOnboardingPage()));
    await tester.pumpAndSettle();

    expect(find.text('请完成 6 道题'), findsOneWidget);
    expect(find.text('已完成 0/0 题'), findsOneWidget);
  });

  testWidgets('按篇作答后统一提交初始化题', (tester) async {
    coord.initTexts = [_text(41, '严先生祠堂记'), _text(166, '周郑交质')];
    readTracker.markEffectApplied(41);
    readTracker.markEffectApplied(166);

    final questions = _fakeInitQuestions();
    addTearDown(() => calloc.free(questions.first.owner));
    final repo = _FakeInitRepo(initialized: false)..questions = questions;
    userCtrl.initTracker(_NoopTracker());
    userCtrl.initUserInitRepository(repo);
    userCtrl.setUser(User.allocate(calloc));

    SharedPreferences.setMockInitialValues({kInitQuizGuideSeenKey: true});
    await tester.pumpWidget(wrap(const InitOnboardingPage()));
    await tester.pumpAndSettle();

    expect(find.text('请完成 6 道题'), findsOneWidget);

    // 第一篇：进入按篇答题，完成 3 题后返回
    await tester.tap(find.text('做题').first);
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('选项1'));
      await tester.pump();
      if (i < 2) {
        await tester.tap(find.text('下一题'));
        await tester.pumpAndSettle();
      }
    }
    await tester.tap(find.text('完成本篇'));
    await tester.pumpAndSettle();
    expect(find.text('已完成 3/6 题'), findsOneWidget);

    // 第二篇：完成 3 题后返回
    await tester.tap(find.text('做题').last);
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('选项1'));
      await tester.pump();
      if (i < 2) {
        await tester.tap(find.text('下一题'));
        await tester.pumpAndSettle();
      }
    }
    await tester.tap(find.text('完成本篇'));
    await tester.pumpAndSettle();
    expect(find.text('已完成 6/6 题'), findsOneWidget);
    expect(find.text('提交 6 题初始化'), findsOneWidget);

    // 统一提交：一次传入 6 个 qid/choice
    await tester.tap(find.text('提交 6 题初始化'));
    await tester.pumpAndSettle();

    expect(repo.lastQids, isNotNull);
    expect(repo.lastQids!.length, 6);
    expect(repo.lastChoices, everyElement(0));
    expect(find.text('初始化完成'), findsOneWidget);
  });

  testWidgets('已初始化时显示完成态', (tester) async {
    userCtrl.initUserInitRepository(_FakeInitRepo(initialized: true));
    userCtrl.refreshInitState();
    await tester.pumpWidget(wrap(const InitOnboardingPage()));
    await tester.pumpAndSettle();

    expect(find.text('初始化完成'), findsOneWidget);
    expect(find.text('已完成初始化，可以开始学习了'), findsOneWidget);
  });

  group('F1 初始化操作教程', () {
    testWidgets('第一篇首次进入显示 3 步并可完成', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(wrap(InitReadingPage(
        text: _text(41, '严先生祠堂记'),
        annotations: const {1: '注释'},
        translation: '译文',
        showTutorial: true,
      )));
      await tester.pumpAndSettle();

      expect(find.text('点击带圈数字查看注释'), findsOneWidget);
      expect(find.text('跳过引导'), findsOneWidget);
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('点击这里对照译文'), findsOneWidget);

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('点击翻页继续阅读'), findsOneWidget);

      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.text('点击翻页继续阅读'), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kInitTutorialSeenKey), isTrue);
    });

    testWidgets('第一篇有初始化题时显示第 4 步，从做题返回后引导完成', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final questions = _fakeInitQuestions().sublist(0, 3);
      addTearDown(() => calloc.free(questions.first.owner));
      await tester.pumpWidget(wrap(InitReadingPage(
        text: _text(41, '严先生祠堂记'),
        annotations: const {1: '注释'},
        translation: '译文',
        showTutorial: true,
        articleQuestions: questions,
        initAnswers: {100: null, 101: null, 102: null},
      )));
      await tester.pumpAndSettle();

      // 前 3 步后进入第 4 步“做题”。
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('下一步'));
        await tester.pumpAndSettle();
      }
      expect(find.text('第 4/4 步'), findsOneWidget);
      expect(find.text('阅读时可随时点击“做题”进入本篇初始化题'), findsOneWidget);

      // 点击高亮的“做题”进入初始化答题页，再返回。
      await tester.tap(find.text('做题'));
      await tester.pumpAndSettle();
      expect(find.textContaining('初始化答题'), findsOneWidget);
      // 从教程第 4 步进入时，答题页继续展示第 5 步“回看原文”引导。
      expect(find.text('第 5 步'), findsOneWidget);
      expect(find.text('可回看原文对照'), findsOneWidget);
      await tester.tap(find.text('跳过引导'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // 返回后引导应视为完成并写 seen。
      expect(find.text('阅读时可随时点击“做题”进入本篇初始化题'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kInitTutorialSeenKey), isTrue);
      expect(prefs.getBool(kInitQuizGuideSeenKey), isTrue);
    });

    testWidgets('跳过引导写入 seen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(wrap(InitReadingPage(
        text: _text(41, '严先生祠堂记'),
        annotations: const {},
        translation: '',
        showTutorial: true,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('跳过引导'));
      await tester.pumpAndSettle();
      expect(find.text('点击带圈数字查看注释'), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kInitTutorialSeenKey), isTrue);
    });

    testWidgets('seen 后不再显示', (tester) async {
      SharedPreferences.setMockInitialValues({kInitTutorialSeenKey: true});
      await tester.pumpWidget(wrap(InitReadingPage(
        text: _text(41, '严先生祠堂记'),
        annotations: const {},
        translation: '',
        showTutorial: true,
      )));
      await tester.pumpAndSettle();

      expect(find.text('点击带圈数字查看注释'), findsNothing);
      expect(find.text('跳过引导'), findsNothing);
    });

    testWidgets('第二篇不显示教程', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(wrap(InitReadingPage(
        text: _text(166, '周郑交质'),
        annotations: const {},
        translation: '',
        showTutorial: false,
      )));
      await tester.pumpAndSettle();

      expect(find.text('点击带圈数字查看注释'), findsNothing);
      expect(find.text('跳过引导'), findsNothing);
    });

    testWidgets('窄屏下教程可显示', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(480, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(wrap(InitReadingPage(
        text: _text(41, '严先生祠堂记'),
        annotations: const {},
        translation: '',
        showTutorial: true,
      )));
      await tester.pumpAndSettle();

      expect(find.text('点击带圈数字查看注释'), findsOneWidget);
      expect(find.text('跳过引导'), findsOneWidget);
    });

    testWidgets('宽屏下教程可显示', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(wrap(InitReadingPage(
        text: _text(41, '严先生祠堂记'),
        annotations: const {},
        translation: '',
        showTutorial: true,
      )));
      await tester.pumpAndSettle();

      expect(find.text('点击带圈数字查看注释'), findsOneWidget);
      expect(find.text('跳过引导'), findsOneWidget);
    });

    testWidgets('教程高亮时仍可点击译文按钮', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(wrap(InitReadingPage(
        text: _text(41, '严先生祠堂记'),
        annotations: const {},
        translation: '译文',
        showTutorial: true,
      )));
      await tester.pumpAndSettle();

      // 进入第 2 步：高亮“译文对照”按钮。
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      final iconBefore = tester.widget<Icon>(find.byIcon(Icons.translate));
      await tester.tap(find.byIcon(Icons.translate), warnIfMissed: false);
      await tester.pumpAndSettle();
      final iconAfter = tester.widget<Icon>(find.byIcon(Icons.translate));

      expect(iconAfter.color, isNot(iconBefore.color));
      // 引导仍应保持打开。
      expect(find.text('点击这里对照译文'), findsOneWidget);
    });
  });
}

class _FakeInitRepo implements UserInitRepository {
  final bool initialized;
  List<Question> questions = [];
  List<int>? lastQids;
  List<int>? lastChoices;
  int disposeCount = 0;

  _FakeInitRepo({required this.initialized});

  @override
  bool isInitialized() => initialized;

  @override
  List<Question> initQuestions() => questions;

  @override
  void disposeInitQuestions(List<Question> qs) {
    if (qs.isNotEmpty) disposeCount++;
  }

  @override
  User? applyInit(List<int> qids, List<int> choices) {
    lastQids = List.of(qids);
    lastChoices = List.of(choices);
    return User.allocate(calloc);
  }
}
