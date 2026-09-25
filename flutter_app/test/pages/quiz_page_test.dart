import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/quiz_test_support.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/pages/quiz_page.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/widgets/init_quiz_guide_overlay.dart';

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

/// 把答题页挂在宿主页里推入导航栈：退出轻确认用例需要验证 pop 后回到宿主。
Widget _pushQuizHost(Widget Function() buildQuiz) {
  return Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => buildQuiz()),
          ),
          child: const Text('打开答题'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('QuizPage 渲染题干、选项与题型徽标', (tester) async {
    setQuizViewport(tester, height: 1000);
    final questions = fakeQuestions(2);

    await tester.pumpWidget(wrapQuizPage(QuizPage(
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
    setQuizViewport(tester, height: 1000);
    final questions = fakeQuestions(2);
    writeQuestionStr(questions[0].ptr.ref.qType, 'xuci');
    writeQuestionStr(questions[1].ptr.ref.qType, 'duanju');

    await tester.pumpWidget(wrapQuizPage(QuizPage(
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
    setQuizViewport(tester, height: 1000);
    final questions = fakeQuestions(1);
    final q = questions.first;
    writeQuestionStr(q.ptr.ref.context, '项脊轩，旧南阁子也');
    q.ptr.ref.markStart = 4;
    q.ptr.ref.markLen = 1;

    await tester.pumpWidget(wrapQuizPage(QuizPage(
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
    final markStyle = findUnderlinedMark(rich.text, '旧');
    expect(markStyle, isNotNull);
    expect(markStyle!.decoration, TextDecoration.underline);
    // 划线颜色随主题强调色（默认朱砂），断言取当前主题 primary 而非硬编码
    final scheme = Theme.of(tester.element(find.byType(QuizPage))).colorScheme;
    expect(markStyle.color, scheme.primary);
  });

  testWidgets('无原句题目：不渲染额外句子', (tester) async {
    setQuizViewport(tester, height: 1000);
    final questions = fakeQuestions(1);

    await tester.pumpWidget(wrapQuizPage(QuizPage(
      articleTitle: '岳阳楼记',
      questions: questions,
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('原句', findRichText: true), findsNothing);
  });

  testWidgets('选择选项前进后退，末题变为提交并校验必答', (tester) async {
    setQuizViewport(tester, height: 1000);
    final questions = fakeQuestions(2);

    await tester.pumpWidget(wrapQuizPage(QuizPage(
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

  testWidgets('未作答时「下一题」为次按钮样式，选中后恢复主按钮（P3 降级样式）',
      (tester) async {
    setQuizViewport(tester, height: 1000);
    final questions = fakeQuestions(2);

    await tester.pumpWidget(wrapQuizPage(QuizPage(
      articleTitle: '岳阳楼记',
      questions: questions,
    )));
    await tester.pumpAndSettle();

    // 未作答：次按钮，但仍可点（行为不变：不强制作答）
    final nextOutlined = find.widgetWithText(OutlinedButton, '下一题');
    expect(nextOutlined, findsOneWidget);
    expect(tester.widget<OutlinedButton>(nextOutlined).onPressed, isNotNull);
    expect(find.widgetWithText(FilledButton, '下一题'), findsNothing);

    // 选中后恢复主按钮
    await tester.tap(find.text('选项2释义'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '下一题'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '下一题'), findsNothing);
  });

  testWidgets('数据同步中（syncing）提交被短路：提示稍后重试，不判分', (tester) async {
    setQuizViewport(tester, height: 1000);
    final questions = fakeQuestions(1);

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

    await tester.pumpWidget(wrapQuizPage(
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
    setQuizViewport(tester, height: 1000);
    final questions = fakeQuestions(2);

    await tester.pumpWidget(wrapQuizPage(QuizPage(
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

  testWidgets('成功提交 → pushReplacement 结果页：渲染统计与解析（H1 回归：结果页读题内存须仍有效）',
      (tester) async {
    setQuizViewport(tester, height: 1200);
    final questions = fakeQuestions(2);

    final settingsCtrl = SettingsController();
    final userCtrl = UserController();
    final tracker = _FakeQuizTracker();
    userCtrl.initTracker(tracker);
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);
    await tester.pumpWidget(wrapQuizPage(
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
    setQuizViewport(tester, height: 1200);
    final questions = fakeQuestions(2);

    final settingsCtrl = SettingsController();
    final userCtrl = UserController();
    final tracker = _FakeQuizTracker();
    userCtrl.initTracker(tracker);
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);
    await tester.pumpWidget(wrapQuizPage(
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

  testWidgets('选项选中态暴露到语义树（读屏/自动化可断言）', (tester) async {
    setQuizViewport(tester, height: 1000);
    final handle = tester.ensureSemantics();
    final questions = fakeQuestions(1);

    await tester.pumpWidget(wrapQuizPage(QuizPage(
      articleTitle: '岳阳楼记',
      questions: questions,
    )));
    await tester.pumpAndSettle();

    // 初始四选项皆未选中，且都作为按钮暴露。
    const letters = ['A', 'B', 'C', 'D'];
    for (var i = 0; i < 4; i++) {
      expect(
        tester.getSemantics(find.text('选项${i + 1}释义')),
        isSemantics(
          isSelected: false,
          isButton: true,
          label: '选项 ${letters[i]}：选项${i + 1}释义\n选项${i + 1}释义',
        ),
        reason: '选项${i + 1}应作为未选中按钮暴露',
      );
    }

    await tester.tap(find.text('选项2释义'));
    await tester.pumpAndSettle();

    // 回归点：改前语义树里四项恒 selected=false，验收只能靠人眼看截图。
    expect(
      tester.getSemantics(find.text('选项2释义')),
      isSemantics(
        isSelected: true,
        isButton: true,
        label: '选项 B：选项2释义\n选项2释义',
      ),
    );
    expect(
      tester.getSemantics(find.text('选项1释义')),
      isSemantics(isSelected: false, isButton: true),
    );
    handle.dispose();
  });

  testWidgets('AppBar 返回按钮带中文语义标签', (tester) async {
    setQuizViewport(tester, height: 1000);
    final handle = tester.ensureSemantics();
    final questions = fakeQuestions(1);

    await tester.pumpWidget(wrapQuizPage(QuizPage(
      articleTitle: '岳阳楼记',
      questions: questions,
    )));
    await tester.pumpAndSettle();

    // 改前图标按钮没有 content-desc，既读不出用途也无法被自动化定位。
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(
      tester.getSemantics(find.byIcon(Icons.arrow_back)),
      isSemantics(tooltip: '返回'),
    );
    handle.dispose();
  });

  testWidgets('AppBar 切换按钮进入只读原文，并可切回题目', (tester) async {
    setQuizViewport(tester, height: 1200);
    final questions = fakeQuestions(1);

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

    await tester.pumpWidget(wrapQuizPage(
      QuizPage(
        articleTitle: '岳阳楼记',
        questions: questions,
      ),
      coord: coord,
      settingsCtrl: settingsCtrl,
      userCtrl: userCtrl,
    ));
    await tester.pumpAndSettle();

    // 题目视图：不产生新路由，工具栏按钮 tooltip 指向“将要去”的原文
    expect(find.text('第 1/1 题'), findsOneWidget);
    expect(find.byTooltip('查看原文'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.article_outlined));
    await tester.pumpAndSettle();

    // 仍在同一路由内（方案 D：页内视图翻转），原文正文可见
    expect(find.byType(QuizPage), findsOneWidget);
    expect(find.textContaining('庆历四年春', findRichText: true), findsOneWidget);
    expect(find.text('第 1/1 题'), findsNothing);

    // 切回题目：按钮 tooltip 反向，答题视图恢复
    expect(find.byTooltip('返回题目'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.quiz_outlined));
    await tester.pumpAndSettle();
    expect(find.text('第 1/1 题'), findsOneWidget);
    expect(find.byTooltip('查看原文'), findsOneWidget);
  });

  testWidgets('切到原文再切回：已选答案仍在（双视图保活）', (tester) async {
    setQuizViewport(tester, height: 1200);
    final questions = fakeQuestions(2);

    await tester.pumpWidget(wrapQuizPage(QuizPage(
      articleTitle: '岳阳楼记',
      questions: questions,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('选项1释义'));
    await tester.pump();
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选项2释义'));
    await tester.pump();

    // 往返一次原文视图
    await tester.tap(find.byIcon(Icons.article_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.quiz_outlined));
    await tester.pumpAndSettle();

    // 进度与答案都还在：末题已答 → 提交按钮可用
    expect(find.text('第 2/2 题'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });

  testWidgets('原文视图只读：不出现完成/放弃结算入口', (tester) async {
    setQuizViewport(tester, height: 1200);
    final questions = fakeQuestions(1);

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

    await tester.pumpWidget(wrapQuizPage(
      QuizPage(articleTitle: '岳阳楼记', questions: questions),
      coord: coord,
      settingsCtrl: settingsCtrl,
      userCtrl: userCtrl,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.article_outlined));
    await tester.pumpAndSettle();

    // ReadingFrame 的“完成阅读/放弃”不得出现在对照视图里
    expect(find.text('完成阅读'), findsNothing);
    expect(find.text('放弃'), findsNothing);
    expect(find.text('返回'), findsWidgets);
  });

  testWidgets('退出轻确认：继续作答则留在原页，放弃才 pop', (tester) async {
    setQuizViewport(tester, height: 1200);
    final questions = fakeQuestions(2);

    await tester.pumpWidget(wrapQuizPage(_pushQuizHost(
      () => QuizPage(articleTitle: '岳阳楼记', questions: questions),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开答题'));
    await tester.pumpAndSettle();

    // 未作答：直接退出，不弹确认
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('打开答题'), findsOneWidget);

    // 重新进入并作答
    await tester.tap(find.text('打开答题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选项1释义'));
    await tester.pump();

    // 有未提交答案：弹轻确认，选“继续作答”留在答题页
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('放弃本次作答？'), findsOneWidget);
    await tester.tap(find.text('继续作答'));
    await tester.pumpAndSettle();
    expect(find.text('第 1/2 题'), findsOneWidget);

    // 再退一次并确认放弃 → 回到宿主页
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();
    expect(find.text('打开答题'), findsOneWidget);
  });

  testWidgets('活动阅读会话下切原文：计时继续、切回不结算', (tester) async {
    setQuizViewport(tester, height: 1200);
    final questions = fakeQuestions(1);

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
    final userCtrl = UserController()..setUser(User.allocate(calloc));
    final coord = _CountingCoordinator(
      navCtrl: NavigationController(),
      settingsCtrl: settingsCtrl,
      readingCtrl: readingCtrl,
      userCtrl: userCtrl,
      readTracker: readTracker,
    );
    addTearDown(readingCtrl.dispose);
    addTearDown(userCtrl.dispose);

    await tester.pumpWidget(wrapQuizPage(
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
    // 让活动会话的 1s 周期计时器真的走两拍（fake async 下需显式推进时钟）
    await tester.pump(const Duration(seconds: 2));

    final before = readingCtrl.elapsedSeconds;
    expect(before, greaterThan(0), reason: '活动会话应在计时中');

    await tester.tap(find.byIcon(Icons.article_outlined));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    // 复用同一控制器 → 原文视图里计时不停
    expect(readingCtrl.elapsedSeconds, greaterThan(before));

    await tester.tap(find.byIcon(Icons.quiz_outlined));
    await tester.pumpAndSettle();

    // 只切视图不是退出：不结算、会话仍在
    expect(coord.finishCount, 0);
    expect(readingCtrl.isReading, isTrue);

    // 活动会话的周期计时器须在用例内停掉（否则框架报 pending timer）
    readingCtrl.pauseTimer();
  });

  testWidgets('初始化按篇模式退出不确认（进度在共享答案表里）', (tester) async {
    setQuizViewport(tester, height: 1200);
    final questions = fakeQuestions(2);
    final answers = <int, int?>{100: 1, 101: null};

    await tester.pumpWidget(wrapQuizPage(_pushQuizHost(
      () => QuizPage(
        articleTitle: '严先生祠堂记',
        questions: questions,
        isInitPart: true,
        initAnswers: answers,
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开答题'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('放弃本次作答？'), findsNothing);
    expect(find.text('打开答题'), findsOneWidget);
  });

  testWidgets('初始化按篇模式记录答案并返回，不调用 applyInit', (tester) async {
    setQuizViewport(tester, height: 1200);
    final questions = fakeQuestions(2);

    final answers = <int, int?>{100: null, 101: null};
    final userCtrl = UserController()..setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);

    SharedPreferences.setMockInitialValues({kInitQuizGuideSeenKey: true});
    await tester.pumpWidget(wrapQuizPage(
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
    setQuizViewport(tester, height: 1200);
    final questions = fakeQuestions(1);
    final userCtrl = UserController()..setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(wrapQuizPage(
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
    setQuizViewport(tester, height: 1200);
    final questions = fakeQuestions(1);
    final userCtrl = UserController()..setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);

    SharedPreferences.setMockInitialValues({kInitQuizGuideSeenKey: true});
    await tester.pumpWidget(wrapQuizPage(
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
    setQuizViewport(tester, height: 1200);
    final questions = fakeQuestions(1);
    final userCtrl = UserController()..setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(wrapQuizPage(
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
    setQuizViewport(tester, height: 1200);
    final questions = fakeQuestions(2);

    final settingsCtrl = SettingsController();
    final userCtrl = UserController();
    final tracker = _FakeQuizTracker(); // 第 1 题对、第 2 题错
    userCtrl.initTracker(tracker);
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);
    await tester.pumpWidget(wrapQuizPage(
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
    setQuizViewport(tester, height: 1200);
    final questions = fakeQuestions(2);

    final settingsCtrl = SettingsController();
    final userCtrl = UserController();
    final tracker = _FakeQuizTracker()..failFrom = 1; // 第 2 题起失败
    userCtrl.initTracker(tracker);
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);
    await tester.pumpWidget(wrapQuizPage(
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

  testWidgets('活动阅读进入答题并提交：finishReadingSession 恰好一次并丢弃阅读状态', (tester) async {
    setQuizViewport(tester, height: 1200);
    final questions = fakeQuestions(2);

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

    await tester.pumpWidget(wrapQuizPage(
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
    setQuizViewport(tester, height: 1200);
    final questions = fakeQuestions(2);

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

    await tester.pumpWidget(wrapQuizPage(
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
