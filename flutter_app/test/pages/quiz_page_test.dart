import 'dart:convert';
import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/pages/quiz_page.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

Widget _wrap(Widget child) {
  final settingsCtrl = SettingsController();
  final userCtrl = UserController();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settingsCtrl),
      ChangeNotifierProvider.value(value: userCtrl),
    ],
    child: MaterialApp(home: child),
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
  List<Question> getQuestionsByIds(List<int> ids) => [];

  @override
  QuizAttemptSummary? getAttemptSummary(int textId) => null;

  @override
  void disposeQuestions(List<Question> questions) {
    disposeCount++;
  }
}

List<Question> _fakeQuestions(int n) {
  final block = calloc<QuestionData>(n);
  for (int i = 0; i < n; i++) {
    final q = (block + i).ref;
    q.id = 100 + i;
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
    expect(markStyle.color, AppTheme.vermilion);
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
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsCtrl),
        ChangeNotifierProvider<UserController>.value(value: userCtrl),
      ],
      child: MaterialApp(
        home: QuizPage(
          articleTitle: '岳阳楼记',
          questions: questions,
        ),
      ),
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
    expect(find.textContaining('你的答案'), findsNWidgets(2));
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
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsCtrl),
        ChangeNotifierProvider<UserController>.value(value: userCtrl),
      ],
      child: MaterialApp(
        home: QuizPage(
          articleTitle: '岳阳楼记',
          questions: questions,
          isReview: true,
        ),
      ),
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
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsCtrl),
        ChangeNotifierProvider<UserController>.value(value: userCtrl),
      ],
      child: MaterialApp(
        home: QuizPage(
          articleTitle: '岳阳楼记',
          questions: questions,
        ),
      ),
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
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsCtrl),
        ChangeNotifierProvider<UserController>.value(value: userCtrl),
      ],
      child: MaterialApp(
        home: QuizPage(
          articleTitle: '岳阳楼记',
          questions: questions,
        ),
      ),
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
    expect(find.textContaining('你的答案'), findsOneWidget);

    // 部分失败路径：sublist 共享同一 owner 块，仍恰好释放一次
    await tester.pumpWidget(const SizedBox());
    expect(tracker.disposeCount, 1);
  });
}