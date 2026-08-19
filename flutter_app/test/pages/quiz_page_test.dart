import 'dart:convert';
import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/pages/quiz_page.dart';
import 'package:chinese_classical_rec_sys/pages/quiz_result_page.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/init_quiz_guide_overlay.dart';

Widget _wrap(Widget child,
    {AppCoordinator? coord,
    SettingsController? settingsCtrl,
    UserController? userCtrl}) {
  final sCtrl = settingsCtrl ?? SettingsController();
  final uCtrl = userCtrl ?? UserController();
  // QuizPage._submit 读取 AppCoordinator.syncing（数据同步闸门）；测试默认非同步中
  final appCoord = coord ??
      AppCoordinator(
        navCtrl: NavigationController(),
        settingsCtrl: sCtrl,
        readingCtrl: ReadingController(ReadTracker()),
        userCtrl: uCtrl,
        readTracker: ReadTracker(),
      );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: sCtrl),
      ChangeNotifierProvider.value(value: uCtrl),
      Provider.value(value: appCoord),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme(ScreenSize.medium, 1.0,
          accentColor: AppTheme.vermilion),
      darkTheme: AppTheme.darkTheme(ScreenSize.medium, 1.0,
          accentColor: AppTheme.vermilion),
      themeMode: sCtrl.darkMode ? ThemeMode.dark : ThemeMode.light,
      home: child,
    ),
  );
}

/// 模拟成功判分的 tracker（成功提交链路测试用）：
/// 走真实 UserController.submitQuiz，仅 C++ 判题被替换
class _FakeQuizTracker implements QuizTracker {
  int _calls = 0;
  int failFrom = 0; // 第 N 次起判题失败（0 表示全成功）

  /// disposeQuestions 调用次数（验证题目内存恰好释放一次）
  int disposeCount = 0;

  @override
  (User?, bool?) applyQuiz(User user, int questionId, int choice,
      {bool isReview = false}) {
    // 每次必须返回新分配的 User（submitQuiz 会 dispose 中间态）
    if (failFrom > 0 && _calls >= failFrom) {
      _calls++;
      return (null, null);
    }
    final out = User.allocate(calloc);
    final correct = _calls == 0; // 第 1 题对、其余错
    _calls++;
    return (out, correct);
  }

  @override
  User? applyRead(User user, int textId, double readTime) => null;

  @override
  User? prune(User user) => null;

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
  void disposeQuestions(List<Question> questions) {
    disposeCount++;
  }
}

class _PreviewCoordinator extends AppCoordinator {
  _PreviewCoordinator({
    required super.navCtrl,
    required super.settingsCtrl,
    required super.readingCtrl,
    required super.userCtrl,
    required super.readTracker,
  });

  final ChineseText previewText = ChineseText(
    id: 1,
    title: '岳阳楼记',
    author: '范仲淹',
    dynasty: '宋',
    source: '古文观止',
    content: '庆历四年春，滕子京谪守巴陵郡。',
    charCount: 20,
    difficulties: List.filled(10, 0.5),
  );

  @override
  ChineseText? getTextDetail(int textId) =>
      textId == previewText.id ? previewText : null;

  @override
  String getAnnotations(int textId) => '';

  @override
  String getTranslation(int textId) => '';
}

class _CountingCoordinator extends AppCoordinator {
  _CountingCoordinator({
    required super.navCtrl,
    required super.settingsCtrl,
    required super.readingCtrl,
    required super.userCtrl,
    required super.readTracker,
  });

  int finishCount = 0;

  @override
  void finishReadingSession() {
    finishCount++;
    super.finishReadingSession();
  }
}

List<Question> _fakeQuestions(int n) {
  final block = calloc<QuestionData>(n);
  for (int i = 0; i < n; i++) {
    final q = (block + i).ref;
    q.id = 100 + i;
    q.textId = 1;
    _writeStr(q.qType, 'shici');
    _writeStr(q.stem, '第${i + 1}题题干：加点词解释');
    for (int k = 0; k < 4; k++) {
      // options 为扁平 2048 字节（与 C++ char[4][512] 布局一致），按 512 偏移写
      _writeStr(q.options, '选项${k + 1}释义', offset: k * 512);
    }
    _writeStr(q.dims, '3,4,9');
    _writeStr(q.explanation, '第${i + 1}题解析');
    q.difficulty = 0.5;
  }
  return [
    for (int i = 0; i < n; i++) Question(block + i, owner: block),
  ];
}

void _writeStr(Array<Uint8> arr, String s, {int offset = 0}) {
  final bytes = utf8.encode(s);
  for (int i = 0; i < bytes.length && i < 512; i++) {
    arr[offset + i] = bytes[i];
  }
  arr[offset + bytes.length] = 0;
}

/// 在 TextSpan 树里找带下划线样式的目标词 span
TextStyle? _findMarkStyle(InlineSpan span, String word) {
  if (span is TextSpan) {
    if (span.text == word &&
        span.style?.decoration == TextDecoration.underline) {
      return span.style;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      final hit = _findMarkStyle(child, word);
      if (hit != null) return hit;
    }
  }
  return null;
}

void main() {
  testWidgets('QuizPage 渲染题干、选项与题型徽标', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(2);
    addTearDown(() => calloc.free(questions.first.owner));

    await tester.pumpWidget(_wrap(QuizPage(
      articleTitle: '岳阳楼记',
      questions: questions,
    )));
    await tester.pumpAndSettle();

    expect(find.text('第 1/2 题'), findsOneWidget);
    expect(find.textContaining('第1题题干'), findsOneWidget);
    expect(find.text('诗句理解'), findsOneWidget);
    expect(find.text('选项1释义'), findsOneWidget);
    expect(find.text('选项4释义'), findsOneWidget);
    expect(find.text('下一题'), findsOneWidget);
  });

  testWidgets('新题型 badge：虚词/断句显示中文文案', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(2);
    addTearDown(() => calloc.free(questions.first.owner));
    _writeStr(questions[0].ptr.ref.qType, 'xuci');
    _writeStr(questions[1].ptr.ref.qType, 'duanju');

    await tester.pumpWidget(_wrap(QuizPage(
      articleTitle: '新题型',
      questions: questions,
    )));
    await tester.pumpAndSettle();

    expect(find.text('虚词'), findsOneWidget);
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    expect(find.text('断句'), findsOneWidget);
  });

  testWidgets('带原句题目：题干下渲染划线句并高亮目标词', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(1);
    addTearDown(() => calloc.free(questions.first.owner));
    final q = questions.first;
    _writeStr(q.ptr.ref.context, '项脊轩，旧南阁子也');
    q.ptr.ref.markStart = 4;
    q.ptr.ref.markLen = 1;

    await tester.pumpWidget(_wrap(QuizPage(
      articleTitle: '项脊轩志',
      questions: questions,
    )));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('项脊轩，旧南阁子也', findRichText: true),
      findsOneWidget,
    );
    final rich = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((r) => r.text.toPlainText().contains('旧南阁子'));
    final markStyle = _findMarkStyle(rich.text, '旧');
    expect(markStyle, isNotNull);
    expect(markStyle!.decoration, TextDecoration.underline);
    // 划线颜色随主题强调色（默认朱砂），断言取当前主题 primary 而非硬编码
    final scheme =
        Theme.of(tester.element(find.byType(QuizPage))).colorScheme;
    expect(markStyle.color, scheme.primary);
  });

  testWidgets('无原句题目：不渲染额外句子', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(1);
    addTearDown(() => calloc.free(questions.first.owner));

    await tester.pumpWidget(_wrap(QuizPage(
      articleTitle: '岳阳楼记',
      questions: questions,
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('原句', findRichText: true), findsNothing);
  });

  testWidgets('选择选项前进后退，末题变为提交并校验必答', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(2);
    addTearDown(() => calloc.free(questions.first.owner));

    await tester.pumpWidget(_wrap(QuizPage(
      articleTitle: '岳阳楼记',
      questions: questions,
    )));
    await tester.pumpAndSettle();

    // 未选题时"下一题"可点（不强制），先选题
    await tester.tap(find.text('选项2释义'));
    await tester.pump();
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();

    expect(find.text('第 2/2 题'), findsOneWidget);
    expect(find.text('提交'), findsOneWidget);
    // 末题未答：提交禁用 + 常驻提示还有未答题
    final submitBtn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(submitBtn.onPressed, isNull);
    expect(find.text('还有 1 题未作答，可返回补充后再提交'), findsOneWidget);

    // 答完末题 → 提交可用，提示消失
    await tester.tap(find.text('选项1释义'));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    expect(find.text('还有 1 题未作答，可返回补充后再提交'), findsNothing);

    // 上一题回改
    await tester.tap(find.text('上一题'));
    await tester.pumpAndSettle();
    expect(find.text('第 1/2 题'), findsOneWidget);

    // 无 tracker（未 initTracker）→ 提交失败提示 SnackBar
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选项1释义'));
    await tester.pump();
    await tester.tap(find.text('提交'));
    await tester.pump();
    expect(find.text('提交失败，请重试'), findsOneWidget);
  });

  testWidgets('数据同步中（syncing）提交被短路：提示稍后重试，不判分', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(1);
    addTearDown(() => calloc.free(questions.first.owner));

    final userCtrl = UserController();
    final tracker = _FakeQuizTracker();
    userCtrl.initTracker(tracker);
    final coord = AppCoordinator(
      navCtrl: NavigationController(),
      settingsCtrl: SettingsController(),
      readingCtrl: ReadingController(ReadTracker()),
      userCtrl: userCtrl,
      readTracker: ReadTracker(),
    );
    addTearDown(coord.dispose);
    coord.syncing.value = true; // 模拟 db_replace 替换窗口

    await tester.pumpWidget(_wrap(
      QuizPage(articleTitle: '岳阳楼记', questions: questions),
      coord: coord,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('选项1释义'));
    await tester.pump();
    await tester.tap(find.text('提交'));
    await tester.pump();

    expect(find.text('数据同步中，请稍后重试'), findsOneWidget);
    expect(tracker.disposeCount, 0, reason: '未进入判题链路，题目内存未被释放');
    // 页面未跳转（仍在答题页）
    expect(find.byType(QuizPage), findsOneWidget);
  });

  testWidgets('回改后前进：已答答案保留（提交可用而非被清空）', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(2);
    addTearDown(() => calloc.free(questions.first.owner));

    await tester.pumpWidget(_wrap(QuizPage(
      articleTitle: '岳阳楼记',
      questions: questions,
    )));
    await tester.pumpAndSettle();

    // 第 1 题选"选项1"，第 2 题选"选项2"
    await tester.tap(find.text('选项1释义'));
    await tester.pump();
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选项2释义'));
    await tester.pump();

    // 回第 1 题改选"选项3"
    await tester.tap(find.text('上一题'));
    await tester.pumpAndSettle();
    expect(find.text('第 1/2 题'), findsOneWidget);
    await tester.tap(find.text('选项3释义'));
    await tester.pump();

    // 前进：第 2 题答案保留（非空 → 提交按钮可用，而非被清回禁用）
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    expect(find.text('第 2/2 题'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });

  testWidgets('成功提交 → pushReplacement 结果页：渲染统计与解析（H1 回归：结果页读题内存须仍有效）', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(2);
    addTearDown(() => calloc.free(questions.first.owner));

    final settingsCtrl = SettingsController();
    final userCtrl = UserController();
    final tracker = _FakeQuizTracker();
    userCtrl.initTracker(tracker);
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);
    await tester.pumpWidget(_wrap(
      QuizPage(
        articleTitle: '岳阳楼记',
        questions: questions,
      ),
      settingsCtrl: settingsCtrl,
      userCtrl: userCtrl,
    ));
    await tester.pumpAndSettle();

    // 作答并提交
    await tester.tap(find.text('选项1释义'));
    await tester.pump();
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选项2释义'));
    await tester.pump();
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    // 结果页：统计 + 每题解析（读取题目内存 → UAF 回归点）
    expect(find.textContaining('1 / 2', findRichText: true), findsOneWidget);
    expect(find.textContaining('第1题解析'), findsOneWidget);
    expect(find.textContaining('第2题解析'), findsOneWidget);
    expect(find.text('你的选择'), findsNWidgets(2));
    expect(find.textContaining('你的答案'), findsNothing);
    expect(find.text('返回文库'), findsOneWidget);
    expect(find.textContaining('能力已随作答更新'), findsOneWidget);

    // 题目内存所有权恰好一次释放：拆树后 QuizPage（已置位转移）与结果页都只释放一次
    await tester.pumpWidget(const SizedBox());
    expect(tracker.disposeCount, 1);
  });

  testWidgets('复习模式：标题错题复习，结果页显示复习不改变能力画像', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(2);
    addTearDown(() => calloc.free(questions.first.owner));

    final settingsCtrl = SettingsController();
    final userCtrl = UserController();
    final tracker = _FakeQuizTracker();
    userCtrl.initTracker(tracker);
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);
    await tester.pumpWidget(_wrap(
      QuizPage(
        articleTitle: '岳阳楼记',
        questions: questions,
        isReview: true,
      ),
      settingsCtrl: settingsCtrl,
      userCtrl: userCtrl,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('错题复习'), findsOneWidget);

    await tester.tap(find.text('选项1释义'));
    await tester.pump();
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选项2释义'));
    await tester.pump();
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    expect(find.text('复习不改变能力画像'), findsOneWidget);
    expect(find.textContaining('错题已入复习队列'), findsNothing);
    expect(find.textContaining('能力已随作答更新'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    expect(tracker.disposeCount, 1);
  });

  testWidgets('AppBar 原文按钮打开只读预览', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(1);
    addTearDown(() => calloc.free(questions.first.owner));

    final settingsCtrl = SettingsController();
    final readTracker = ReadTracker();
    final readingCtrl = ReadingController(readTracker);
    final userCtrl = UserController()..setUser(User.allocate(calloc));
    final coord = _PreviewCoordinator(
      navCtrl: NavigationController(),
      settingsCtrl: settingsCtrl,
      readingCtrl: readingCtrl,
      userCtrl: userCtrl,
      readTracker: readTracker,
    );
    addTearDown(() {
      readingCtrl.dispose();
      userCtrl.dispose();
    });

    await tester.pumpWidget(_wrap(
      QuizPage(
        articleTitle: '岳阳楼记',
        questions: questions,
      ),
      coord: coord,
      settingsCtrl: settingsCtrl,
      userCtrl: userCtrl,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu_book));
    await tester.pumpAndSettle();

    expect(find.textContaining('原文 · 岳阳楼记'), findsOneWidget);
    expect(find.textContaining('庆历四年春', findRichText: true), findsOneWidget);
  });

  testWidgets('初始化按篇模式记录答案并返回，不调用 applyInit', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(2);
    addTearDown(() => calloc.free(questions.first.owner));

    final answers = <int, int?>{100: null, 101: null};
    final userCtrl = UserController()..setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);

    SharedPreferences.setMockInitialValues({kInitQuizGuideSeenKey: true});
    await tester.pumpWidget(_wrap(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => QuizPage(
                      articleTitle: '严先生祠堂记',
                      questions: questions,
                      isInitPart: true,
                      initAnswers: answers,
                    ),
                  ),
                );
              },
              child: const Text('打开答题'),
            ),
          ),
        ),
      ),
      userCtrl: userCtrl,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开答题'));
    await tester.pumpAndSettle();
    expect(find.textContaining('初始化答题'), findsOneWidget);

    await tester.tap(find.text('选项1释义'));
    await tester.pump();
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选项2释义'));
    await tester.pump();

    expect(answers[100], 0);
    expect(answers[101], 1);

    await tester.tap(find.text('完成本篇'));
    await tester.pumpAndSettle();
    expect(find.text('打开答题'), findsOneWidget);
    expect(userCtrl.isInitialized, isFalse);
  });

  testWidgets('初始化答题页首次进入展示兜底提示，可跳过并写 seen', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(1);
    addTearDown(() => calloc.free(questions.first.owner));
    final userCtrl = UserController()..setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_wrap(
      QuizPage(
        articleTitle: '严先生祠堂记',
        questions: questions,
        isInitPart: true,
      ),
      userCtrl: userCtrl,
    ));
    await tester.pumpAndSettle();

    expect(find.text('提示'), findsOneWidget);
    expect(find.text('可回看原文对照'), findsOneWidget);
    expect(find.text('返回后答题进度保留'), findsOneWidget);

    await tester.tap(find.text('跳过引导'));
    await tester.pumpAndSettle();

    expect(find.text('可回看原文对照'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kInitQuizGuideSeenKey), isTrue);
  });

  testWidgets('初始化答题页已读引导后不再展示', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(1);
    addTearDown(() => calloc.free(questions.first.owner));
    final userCtrl = UserController()..setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);

    SharedPreferences.setMockInitialValues({kInitQuizGuideSeenKey: true});
    await tester.pumpWidget(_wrap(
      QuizPage(
        articleTitle: '严先生祠堂记',
        questions: questions,
        isInitPart: true,
      ),
      userCtrl: userCtrl,
    ));
    await tester.pumpAndSettle();

    expect(find.text('提示'), findsNothing);
    expect(find.text('可回看原文对照'), findsNothing);
  });

  testWidgets('showQuizGuide 为 true 时展示第 5 步并写入 seen', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(1);
    addTearDown(() => calloc.free(questions.first.owner));
    final userCtrl = UserController()..setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_wrap(
      QuizPage(
        articleTitle: '严先生祠堂记',
        questions: questions,
        isInitPart: true,
        showQuizGuide: true,
      ),
      userCtrl: userCtrl,
    ));
    await tester.pumpAndSettle();

    expect(find.text('第 5 步'), findsOneWidget);
    expect(find.text('可回看原文对照'), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    expect(find.text('第 5 步'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kInitQuizGuideSeenKey), isTrue);
  });

  testWidgets('正式测验答错：结果页提示错题已入复习队列', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(2);
    addTearDown(() => calloc.free(questions.first.owner));

    final settingsCtrl = SettingsController();
    final userCtrl = UserController();
    final tracker = _FakeQuizTracker(); // 第 1 题对、第 2 题错
    userCtrl.initTracker(tracker);
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);
    await tester.pumpWidget(_wrap(
      QuizPage(
        articleTitle: '岳阳楼记',
        questions: questions,
      ),
      settingsCtrl: settingsCtrl,
      userCtrl: userCtrl,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('选项1释义'));
    await tester.pump();
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选项2释义'));
    await tester.pump();
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    expect(find.textContaining('错题已入复习队列'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(tracker.disposeCount, 1);
  });

  testWidgets('部分判题失败：跳转结果页，展示已计入题数且不重提', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(2);
    addTearDown(() => calloc.free(questions.first.owner));

    final settingsCtrl = SettingsController();
    final userCtrl = UserController();
    final tracker = _FakeQuizTracker()..failFrom = 1; // 第 2 题起失败
    userCtrl.initTracker(tracker);
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);
    await tester.pumpWidget(_wrap(
      QuizPage(
        articleTitle: '岳阳楼记',
        questions: questions,
      ),
      settingsCtrl: settingsCtrl,
      userCtrl: userCtrl,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('选项1释义'));
    await tester.pump();
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选项2释义'));
    await tester.pump();
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    // 进入结果页而非留在答题页（留在答题页重提会重复计分）
    expect(find.textContaining('仅 1 题计入能力'), findsOneWidget);
    expect(find.text('答题结果 · 岳阳楼记'), findsOneWidget);
    // 只展示已生效的第 1 题，第 2 题不展示
    expect(find.textContaining('第1题解析'), findsOneWidget);
    expect(find.textContaining('第2题解析'), findsNothing);
    expect(find.text('你的选择'), findsOneWidget);
    expect(find.textContaining('你的答案'), findsNothing);

    // 部分失败路径：sublist 共享同一 owner 块，仍恰好释放一次
    await tester.pumpWidget(const SizedBox());
    expect(tracker.disposeCount, 1);
  });

  testWidgets('结果页展示全部选项并标记用户选择与正确答案', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(1);
    addTearDown(() => calloc.free(questions.first.owner));
    _writeStr(questions.first.ptr.ref.explanation, '正确答案：B。解析内容');
    final answers = [
      QuizAnswer(
        questionId: 100,
        selected: 0,
        correct: false,
        abilityBefore: List.filled(10, 0.5),
      ),
    ];

    final userCtrl = UserController();
    userCtrl.initTracker(_FakeQuizTracker());
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);

    await tester.pumpWidget(_wrap(
      QuizResultPage(
        articleTitle: '岳阳楼记',
        answers: answers,
        questions: questions,
      ),
      userCtrl: userCtrl,
    ));
    await tester.pumpAndSettle();

    // 四个选项全部展示
    for (var i = 1; i <= 4; i++) {
      expect(find.text('选项$i释义'), findsOneWidget);
    }
    // 用户选 A、正确答案 B → 只有一个对勾（正确选项标记）
    expect(find.text('你的选择'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('结果页能从解析中的正确答案文本识别正确选项', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(1);
    addTearDown(() => calloc.free(questions.first.owner));
    // 真实数据格式：正确答案后跟选项文本，而不是字母。
    _writeStr(questions.first.ptr.ref.explanation, '正确答案：选项3释义。解析内容');
    final answers = [
      QuizAnswer(
        questionId: 100,
        selected: 0,
        correct: false,
        abilityBefore: List.filled(10, 0.5),
      ),
    ];

    final userCtrl = UserController();
    userCtrl.initTracker(_FakeQuizTracker());
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);

    await tester.pumpWidget(_wrap(
      QuizResultPage(
        articleTitle: '岳阳楼记',
        answers: answers,
        questions: questions,
      ),
      userCtrl: userCtrl,
    ));
    await tester.pumpAndSettle();

    // 用户选 A、正确答案是选项3释义 → 应有一个绿色对勾标记正确选项
    expect(find.text('你的选择'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('活动阅读进入答题并提交：finishReadingSession 恰好一次并丢弃阅读状态', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(2);
    addTearDown(() => calloc.free(questions.first.owner));

    final settingsCtrl = SettingsController();
    final readTracker = ReadTracker();
    final readingCtrl = ReadingController(readTracker);
    readingCtrl.loadText(ChineseText(
      id: 1,
      title: '岳阳楼记',
      author: '范仲淹',
      dynasty: '宋',
      source: '古文观止',
      content: '庆历四年春，滕子京谪守巴陵郡。',
      charCount: 20,
      difficulties: List.filled(10, 0.5),
    ));
    final userCtrl = UserController();
    final tracker = _FakeQuizTracker();
    userCtrl.initTracker(tracker);
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);
    final coord = _CountingCoordinator(
      navCtrl: NavigationController(),
      settingsCtrl: settingsCtrl,
      readingCtrl: readingCtrl,
      userCtrl: userCtrl,
      readTracker: readTracker,
    );
    addTearDown(readingCtrl.dispose);

    await tester.pumpWidget(_wrap(
      QuizPage(
        articleTitle: '岳阳楼记',
        questions: questions,
        readingController: readingCtrl,
      ),
      coord: coord,
      settingsCtrl: settingsCtrl,
      userCtrl: userCtrl,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('选项1释义'));
    await tester.pump();
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选项2释义'));
    await tester.pump();
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    expect(coord.finishCount, 1);
    expect(readingCtrl.isReading, isFalse);
  });

  testWidgets('活动阅读进入答题后返回：不结算且阅读状态保留', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final questions = _fakeQuestions(2);
    addTearDown(() => calloc.free(questions.first.owner));

    final settingsCtrl = SettingsController();
    final readTracker = ReadTracker();
    final readingCtrl = ReadingController(readTracker);
    readingCtrl.loadText(ChineseText(
      id: 1,
      title: '岳阳楼记',
      author: '范仲淹',
      dynasty: '宋',
      source: '古文观止',
      content: '庆历四年春，滕子京谪守巴陵郡。',
      charCount: 20,
      difficulties: List.filled(10, 0.5),
    ));
    final userCtrl = UserController();
    userCtrl.initTracker(_FakeQuizTracker());
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);
    final coord = _CountingCoordinator(
      navCtrl: NavigationController(),
      settingsCtrl: settingsCtrl,
      readingCtrl: readingCtrl,
      userCtrl: userCtrl,
      readTracker: readTracker,
    );

    await tester.pumpWidget(_wrap(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => QuizPage(
                      articleTitle: '岳阳楼记',
                      questions: questions,
                      readingController: readingCtrl,
                    ),
                  ),
                );
              },
              child: const Text('打开答题'),
            ),
          ),
        ),
      ),
      coord: coord,
      settingsCtrl: settingsCtrl,
      userCtrl: userCtrl,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开答题'));
    await tester.pumpAndSettle();
    expect(find.text('第 1/2 题'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('打开答题'), findsOneWidget);
    expect(coord.finishCount, 0);
    expect(readingCtrl.isReading, isTrue);
    readingCtrl.dispose();
  });
}
