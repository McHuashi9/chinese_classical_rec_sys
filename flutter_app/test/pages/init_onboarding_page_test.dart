import 'dart:convert';
import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/engine/algorithm_constants.dart';
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

  /// 测试环境没有 C++ 引擎，这里直接把阅读效应落进 ReadTracker，
  /// 语义与生产 [AppCoordinator.recordInitRead] 成功路径一致。
  int recordInitReadCalls = 0;
  int? lastRecordedTextId;

  @override
  bool recordInitRead(int textId, double seconds) {
    recordInitReadCalls++;
    lastRecordedTextId = textId;
    readTracker.saveDuration(textId, seconds.round());
    readTracker.markEffectApplied(textId);
    return true;
  }

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
    // 门禁是「已读 && 已答满」两条，按钮必须点名还缺哪一条。
    expect(find.text('还需阅读：严先生祠堂记、周郑交质'), findsOneWidget);
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

  group('P0 初始化门禁文案与阅读进度可见性', () {
    late _FakeCoordinator p0Coord;

    setUp(() {
      p0Coord = _FakeCoordinator(
        navCtrl: navCtrl,
        settingsCtrl: settingsCtrl,
        readingCtrl: readingCtrl,
        userCtrl: userCtrl,
        readTracker: readTracker,
      );
    });

    Widget wrapP0(Widget child) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: navCtrl),
          ChangeNotifierProvider.value(value: settingsCtrl),
          ChangeNotifierProvider.value(value: readingCtrl),
          ChangeNotifierProvider<UserController>.value(value: userCtrl),
          Provider<AppCoordinator>.value(value: p0Coord),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme(ScreenSize.medium, 1.0,
              accentColor: AppTheme.vermilion),
          home: child,
        ),
      );
    }

    /// 读满一篇（倒计时归零后点「完成」＝走生产 recordInitRead 路径）。
    Future<void> completeReading(WidgetTester tester, int charCount) async {
      await tester.tap(find.text('阅读').first);
      await tester.pumpAndSettle();
      final need = (charCount / maxReadSpeed * 60).ceil() + 1;
      for (var i = 0; i < need; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('完成'), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
    }

    /// 进入 [title] 篇的初始化答题页并答完 3 题（不做任何阅读）。
    ///
    /// 按篇目卡片定位「做题」：篇 1 读完后按钮由「阅读」变为「做题」，
    /// 用 `.first` 会稳定命中部已读完的那一篇。
    Future<void> answerArticle(WidgetTester tester, String title) async {
      final card = find.ancestor(
        of: find.text(title),
        matching: find.byType(Card),
      );
      await tester.tap(find.descendant(of: card, matching: find.text('做题')));
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
    }

    Future<void> pumpOnboarding(WidgetTester tester) async {
      // 关掉一次性的操作教程浮层，否则它会拦住「做题」按钮的点击。
      SharedPreferences.setMockInitialValues({
        kInitTutorialSeenKey: true,
        kInitQuizGuideSeenKey: true,
      });
      await tester.pumpWidget(wrapP0(const InitOnboardingPage()));
      await tester.pumpAndSettle();
    }

    test('门禁文案分支：缺阅读 → 点名篇目；缺答题 → 要求答题；齐了 → 可提交', () {
      // 核心回归：题答满但阅读未达标时，文案不能再是「请先阅读两篇文章」
      // （用户会以为系统没识别到已读，v1.3.0 验收实测卡住人）。
      expect(
        initGateButtonLabel(
          allRead: false,
          allAnswered: true,
          unreadTitles: const ['周郑交质'],
          initQuestionCount: 6,
        ),
        '还需阅读：周郑交质',
      );
      expect(
        initGateButtonLabel(
          allRead: false,
          allAnswered: true,
          unreadTitles: const ['严先生祠堂记', '周郑交质'],
          initQuestionCount: 6,
        ),
        '还需阅读：严先生祠堂记、周郑交质',
      );
      expect(
        initGateButtonLabel(
          allRead: false,
          allAnswered: false,
          unreadTitles: const ['a', 'b', 'c'],
          initQuestionCount: 6,
        ),
        '还需阅读 3 篇',
      );
      expect(
        initGateButtonLabel(
          allRead: false,
          allAnswered: false,
          unreadTitles: const [],
          initQuestionCount: 6,
        ),
        '请先阅读下面两篇文章',
      );
      expect(
        initGateButtonLabel(
          allRead: true,
          allAnswered: false,
          unreadTitles: const [],
          initQuestionCount: 6,
        ),
        '请完成 6 道题',
      );
      expect(
        initGateButtonLabel(
          allRead: true,
          allAnswered: true,
          unreadTitles: const [],
          initQuestionCount: 6,
        ),
        '提交 6 题初始化',
      );
    });

    testWidgets('读满一篇并答完该篇：门禁文案指向剩下一篇、按钮仍禁用', (tester) async {
      p0Coord.initTexts = [_text(41, '严先生祠堂记'), _text(166, '周郑交质')];
      p0Coord.detailOverride = _text(41, '严先生祠堂记');
      final questions = _fakeInitQuestions();
      addTearDown(() => calloc.free(questions.first.owner));
      userCtrl.initTracker(_NoopTracker());
      userCtrl.initUserInitRepository(
          _FakeInitRepo(initialized: false)..questions = questions);
      userCtrl.setUser(User.allocate(calloc));

      await pumpOnboarding(tester);

      // 列表条目自带阅读进度：用户知道还要读多久，不用去阅读器里干等。
      expect(find.textContaining('未读 · 还需'), findsNWidgets(2));

      await completeReading(tester, 10);
      await answerArticle(tester, '严先生祠堂记');

      expect(find.text('已完成 3/6 题'), findsOneWidget);
      expect(find.text('请先阅读两篇文章'), findsNothing);
      expect(find.text('还需阅读：周郑交质'), findsOneWidget);
      // 「已读」标记只在已读完那一篇的卡片上，另一篇仍是「阅读」按钮。
      expect(find.text('已读'), findsOneWidget);
      expect(find.text('阅读'), findsOneWidget);
      final gate = tester.widget<FilledButton>(find.ancestor(
        of: find.text('还需阅读：周郑交质'),
        matching: find.byType(FilledButton),
      ));
      expect(gate.onPressed, isNull, reason: '阅读未达标，门禁应保持禁用');
    });

    testWidgets('读完第一篇后：文案点名剩余篇目', (tester) async {
      p0Coord.initTexts = [_text(41, '严先生祠堂记'), _text(166, '周郑交质')];
      readTracker.markEffectApplied(41);
      await tester.pumpWidget(wrapP0(const InitOnboardingPage()));
      await tester.pumpAndSettle();

      expect(find.text('还需阅读：周郑交质'), findsOneWidget);
      expect(find.text('已读'), findsOneWidget);
      expect(find.textContaining('未读 · 还需'), findsOneWidget);
    });

    testWidgets('阅读器点「放弃」：不记已读、不写初始化阅读记录', (tester) async {
      p0Coord.initTexts = [_text(41, '严先生祠堂记')];
      p0Coord.detailOverride = _text(41, '严先生祠堂记');
      SharedPreferences.setMockInitialValues({kInitTutorialSeenKey: true});
      await tester.pumpWidget(wrapP0(const InitOnboardingPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('阅读').first);
      await tester.pumpAndSettle();
      // 一进来就放弃（远未达阈值）：真机实测此处曾直接记为已读。
      await tester.tap(find.text('放弃'));
      await tester.pumpAndSettle();
      expect(find.text('放弃阅读？'), findsOneWidget);

      // 弹窗的「放弃」在阅读器自己的「放弃」之后，取最后一个。
      await tester.tap(find.widgetWithText(TextButton, '放弃').last);
      await tester.pumpAndSettle();

      expect(p0Coord.recordInitReadCalls, 0, reason: '放弃不应写初始化阅读记录');
      expect(readTracker.isTextRead(41), isFalse, reason: '放弃不应记为已读');
      // 回到引导页，该篇仍需阅读。
      expect(find.text('还需阅读：严先生祠堂记'), findsOneWidget);
    });

    testWidgets('未达标退出阅读后：条目显示累计进度，不谎报已读', (tester) async {
      p0Coord.initTexts = [_text(41, '严先生祠堂记')];
      p0Coord.detailOverride = _text(41, '严先生祠堂记');
      readTracker.saveDuration(41, 3);
      await tester.pumpWidget(wrapP0(const InitOnboardingPage()));
      await tester.pumpAndSettle();

      expect(readTracker.isTextRead(41), isFalse);
      // charCount=10 → 达标 4s，已累计 3s → 还需 1s。
      expect(find.textContaining('未读 · 还需 1s'), findsOneWidget);
      expect(find.text('还需阅读：严先生祠堂记'), findsOneWidget);
    });
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
