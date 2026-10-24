import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/quiz_test_support.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:chinese_classical_rec_sys/engine/one_shot_guide.dart';

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

/// 答题页 widget 测试的公共挂载：视口 + 伪题目 + provider 包装 + 首帧 settle。
///
/// [questions] 省略时按 [n] 新建；需在挂载前改写题目字段（原句/题型）的用例
/// 自行构造后传入。返回实际挂载的题目列表，供内存所有权断言复用。
/// [inHost] 时经 [_pushQuizHost] 推入导航栈并点开，用于验证 pop 回宿主。
/// [preview] 为只读原文对照用例装配 [_PreviewCoordinator]（含阅读/用户控制器与收尾），
/// 此时忽略传入的 [coord] / [settingsCtrl] / [userCtrl] / [readingController]。
Future<List<Question>> _pumpQuiz(
  WidgetTester tester, {
  int n = 1,
  List<Question>? questions,
  String articleTitle = '岳阳楼记',
  double height = 1000,
  bool isReview = false,
  bool isInitPart = false,
  Map<int, int?>? initAnswers,
  bool showQuizGuide = false,
  bool inHost = false,
  bool preview = false,
  AppCoordinator? coord,
  SettingsController? settingsCtrl,
  UserController? userCtrl,
  ReadingController? readingController,
}) async {
  final quizQuestions = questions ?? fakeQuestions(n);
  setQuizViewport(tester, height: height);
  var effectiveCoord = coord;
  var effectiveSettingsCtrl = settingsCtrl;
  var effectiveUserCtrl = userCtrl;
  if (preview) {
    final readTracker = ReadTracker();
    final readingCtrl = ReadingController(readTracker);
    final previewUserCtrl = UserController()..setUser(User.allocate(calloc));
    final previewSettingsCtrl = SettingsController();
    effectiveUserCtrl = previewUserCtrl;
    effectiveSettingsCtrl = previewSettingsCtrl;
    effectiveCoord = _PreviewCoordinator(
      navCtrl: NavigationController(),
      settingsCtrl: previewSettingsCtrl,
      readingCtrl: readingCtrl,
      userCtrl: previewUserCtrl,
      readTracker: readTracker,
    );
    addTearDown(() {
      readingCtrl.dispose();
      previewUserCtrl.dispose();
    });
  }
  final page = QuizPage(
    articleTitle: articleTitle,
    questions: quizQuestions,
    isReview: isReview,
    isInitPart: isInitPart,
    initAnswers: initAnswers,
    showQuizGuide: showQuizGuide,
    readingController: readingController,
  );
  await tester.pumpWidget(wrapQuizPage(
    inHost ? _pushQuizHost(() => page) : page,
    coord: effectiveCoord,
    settingsCtrl: effectiveSettingsCtrl,
    userCtrl: effectiveUserCtrl,
  ));
  await tester.pumpAndSettle();
  if (inHost) {
    await tester.tap(find.text('打开答题'));
    await tester.pumpAndSettle();
  }
  return quizQuestions;
}

/// 初始化按篇答题页的公共挂载：在 [_pumpQuiz] 上叠加 seen 标记与引导开关。
///
/// [seen] 写入 [kInitQuizGuideSeenKey] 模拟“引导已读”；[showGuide] 透传
/// `QuizPage.showQuizGuide`（阅读教程第 4 步进入 → 强制展示第 5 步）。
/// [answers] 为按篇模式的共享答案表；[inHost] 见 [_pumpQuiz]。
/// 返回持有 owner 的 [UserController]（用完自动 dispose），供 `isInitialized` 断言。
Future<UserController> _pumpInitQuiz(
  WidgetTester tester, {
  int n = 1,
  bool seen = false,
  bool showGuide = false,
  bool inHost = false,
  Map<int, int?>? answers,
}) async {
  final userCtrl = UserController()..setUser(User.allocate(calloc));
  addTearDown(userCtrl.dispose);
  SharedPreferences.setMockInitialValues(
      seen ? const {kInitQuizGuideSeenKey: true} : const {});
  await _pumpQuiz(
    tester,
    n: n,
    articleTitle: '严先生祠堂记',
    height: 1200,
    isInitPart: true,
    initAnswers: answers,
    showQuizGuide: showGuide,
    inHost: inHost,
    userCtrl: userCtrl,
  );
  return userCtrl;
}

void main() {
  testWidgets('QuizPage 渲染题干、选项与题型徽标', (tester) async {
    await _pumpQuiz(tester, n: 2);

    expect(find.text('第 1/2 题'), findsOneWidget);
    expect(find.textContaining('第1题题干'), findsOneWidget);
    expect(find.text('诗句理解'), findsOneWidget);
    expect(find.text('选项1释义'), findsOneWidget);
    expect(find.text('选项4释义'), findsOneWidget);
    expect(find.text('下一题'), findsOneWidget);
  });

  testWidgets('新题型 badge：虚词/断句显示中文文案', (tester) async {
    final questions = fakeQuestions(2);
    writeQuestionStr(questions[0].ptr.ref.qType, 'xuci');
    writeQuestionStr(questions[1].ptr.ref.qType, 'duanju');

    await _pumpQuiz(tester, questions: questions, articleTitle: '新题型');

    expect(find.text('虚词'), findsOneWidget);
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    expect(find.text('断句'), findsOneWidget);
  });

  testWidgets('带原句题目：题干下渲染划线句并高亮目标词', (tester) async {
    final questions = fakeQuestions(1);
    final q = questions.first;
    writeQuestionStr(q.ptr.ref.context, '项脊轩，旧南阁子也');
    q.ptr.ref.markStart = 4;
    q.ptr.ref.markLen = 1;

    await _pumpQuiz(tester, questions: questions, articleTitle: '项脊轩志');

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
    await _pumpQuiz(tester);

    expect(find.textContaining('原句', findRichText: true), findsNothing);
  });

  testWidgets('选择选项前进后退，末题变为提交并校验必答', (tester) async {
    await _pumpQuiz(tester, n: 2);

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

  testWidgets('未作答时“下一题”为次按钮样式，选中后恢复主按钮（P3 降级样式）', (tester) async {
    await _pumpQuiz(tester, n: 2);

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
    final userCtrl = UserController();
    final tracker = FakeQuizTracker();
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

    await _pumpQuiz(tester, coord: coord);

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
    await _pumpQuiz(tester, n: 2);

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
    final settingsCtrl = SettingsController();
    final userCtrl = UserController();
    final tracker = FakeQuizTracker();
    userCtrl.initTracker(tracker);
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);
    await _pumpQuiz(
      tester,
      n: 2,
      height: 1200,
      settingsCtrl: settingsCtrl,
      userCtrl: userCtrl,
    );

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
    final settingsCtrl = SettingsController();
    final userCtrl = UserController();
    final tracker = FakeQuizTracker();
    userCtrl.initTracker(tracker);
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);
    await _pumpQuiz(
      tester,
      n: 2,
      height: 1200,
      isReview: true,
      settingsCtrl: settingsCtrl,
      userCtrl: userCtrl,
    );

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
    final handle = tester.ensureSemantics();
    await _pumpQuiz(tester);

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
    final handle = tester.ensureSemantics();
    await _pumpQuiz(tester);

    // 改前图标按钮没有 content-desc，既读不出用途也无法被自动化定位。
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(
      tester.getSemantics(find.byIcon(Icons.arrow_back)),
      isSemantics(tooltip: '返回'),
    );
    handle.dispose();
  });

  testWidgets('AppBar 切换按钮进入只读原文，并可切回题目', (tester) async {
    await _pumpQuiz(tester, height: 1200, preview: true);

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
    await _pumpQuiz(tester, n: 2, height: 1200);

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
    await _pumpQuiz(tester, height: 1200, preview: true);
    await tester.tap(find.byIcon(Icons.article_outlined));
    await tester.pumpAndSettle();

    // ReadingFrame 的“完成阅读/放弃”不得出现在对照视图里
    expect(find.text('完成阅读'), findsNothing);
    expect(find.text('放弃'), findsNothing);
    expect(find.text('返回'), findsWidgets);
  });

  testWidgets('退出轻确认：继续作答则留在原页，放弃才 pop', (tester) async {
    await _pumpQuiz(tester, n: 2, height: 1200, inHost: true);

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

    await _pumpQuiz(
      tester,
      height: 1200,
      readingController: readingCtrl,
      coord: coord,
      settingsCtrl: settingsCtrl,
      userCtrl: userCtrl,
    );
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
    final answers = <int, int?>{100: 1, 101: null};
    // 本用例验退出确认语义，引导浮层先标记已读以免遮挡返回键
    await _pumpInitQuiz(tester,
        n: 2, seen: true, answers: answers, inHost: true);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('放弃本次作答？'), findsNothing);
    expect(find.text('打开答题'), findsOneWidget);
  });

  testWidgets('初始化按篇模式记录答案并返回，不调用 applyInit', (tester) async {
    final answers = <int, int?>{100: null, 101: null};
    final userCtrl = await _pumpInitQuiz(
      tester,
      n: 2,
      seen: true,
      answers: answers,
      inHost: true,
    );
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
    await _pumpInitQuiz(tester);

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
    await _pumpInitQuiz(tester, seen: true);

    expect(find.text('提示'), findsNothing);
    expect(find.text('可回看原文对照'), findsNothing);
  });

  testWidgets('showQuizGuide 为 true 时展示第 5 步并写入 seen', (tester) async {
    await _pumpInitQuiz(tester, showGuide: true);

    expect(find.text('第 5 步'), findsOneWidget);
    expect(find.text('可回看原文对照'), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    expect(find.text('第 5 步'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kInitQuizGuideSeenKey), isTrue);
  });

  testWidgets('正式测验答错：结果页提示错题已入复习队列', (tester) async {
    final settingsCtrl = SettingsController();
    final userCtrl = UserController();
    final tracker = FakeQuizTracker(); // 第 1 题对、第 2 题错
    userCtrl.initTracker(tracker);
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);
    await _pumpQuiz(
      tester,
      n: 2,
      height: 1200,
      settingsCtrl: settingsCtrl,
      userCtrl: userCtrl,
    );

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

  testWidgets('批量提交失败：整批回滚，留在答题页可重试且不转移题目所有权', (tester) async {
    final settingsCtrl = SettingsController();
    final userCtrl = UserController();
    final tracker = FakeQuizTracker()..failFrom = 1;
    userCtrl.initTracker(tracker);
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);
    await _pumpQuiz(
      tester,
      n: 2,
      height: 1200,
      settingsCtrl: settingsCtrl,
      userCtrl: userCtrl,
    );

    await tester.tap(find.text('选项1释义'));
    await tester.pump();
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选项2释义'));
    await tester.pump();
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    expect(find.textContaining('本次作答未保存'), findsOneWidget);
    expect(find.text('答题结果 · 岳阳楼记'), findsNothing);
    expect(tracker.batchCalls, 1);
    // 未进入结果页，题目所有权仍归答题页，销毁时释放一次。
    await tester.pumpWidget(const SizedBox());
    expect(tracker.disposeCount, 1);
  });

  testWidgets('活动阅读进入答题并提交：finishReadingSession 恰好一次并丢弃阅读状态', (tester) async {
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
    final tracker = FakeQuizTracker();
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

    await _pumpQuiz(
      tester,
      n: 2,
      height: 1200,
      readingController: readingCtrl,
      coord: coord,
      settingsCtrl: settingsCtrl,
      userCtrl: userCtrl,
    );

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
    userCtrl.initTracker(FakeQuizTracker());
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);
    final coord = _CountingCoordinator(
      navCtrl: NavigationController(),
      settingsCtrl: settingsCtrl,
      readingCtrl: readingCtrl,
      userCtrl: userCtrl,
      readTracker: readTracker,
    );

    await _pumpQuiz(
      tester,
      n: 2,
      height: 1200,
      inHost: true,
      readingController: readingCtrl,
      coord: coord,
      settingsCtrl: settingsCtrl,
      userCtrl: userCtrl,
    );
    expect(find.text('第 1/2 题'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('打开答题'), findsOneWidget);
    expect(coord.finishCount, 0);
    expect(readingCtrl.isReading, isTrue);
    readingCtrl.dispose();
  });

  // 系统返回（Android 手势/导航键）走 PopScope 的真实触发路径：
  // `tester.binding.handlePopRoute()` → WidgetsApp.didPopRoute → Navigator.maybePop
  // → Route.popDisposition → PopScope.onPopInvokedWithResult。
  // 不用 Navigator.pop 绕过，否则测不到拦截逻辑本身。
  group('系统返回键（PopScope）', () {
    testWidgets('有未提交答案时系统返回 → 弹轻确认，确认放弃才退出', (tester) async {
      await _pumpQuiz(tester, n: 2, height: 1200, inHost: true);

      await tester.tap(find.text('选项1释义'));
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // 系统返回与 AppBar 返回箭头等价：先弹确认，未确认不 pop
      expect(find.text('放弃本次作答？'), findsOneWidget);
      expect(find.text('第 1/2 题'), findsOneWidget);
      expect(find.text('打开答题'), findsNothing);

      await tester.tap(find.text('继续作答'));
      await tester.pumpAndSettle();
      expect(find.text('第 1/2 题'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃'));
      await tester.pumpAndSettle();
      expect(find.text('打开答题'), findsOneWidget);
    });

    testWidgets('无未提交答案时系统返回 → 不弹确认，直接退出', (tester) async {
      await _pumpQuiz(tester, n: 2, height: 1200, inHost: true);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('放弃本次作答？'), findsNothing);
      expect(find.text('打开答题'), findsOneWidget);
    });

    testWidgets('初始化按篇模式系统返回不弹确认（进度在共享答案表里）', (tester) async {
      final answers = <int, int?>{100: null, 101: null};
      await _pumpInitQuiz(
        tester,
        n: 2,
        seen: true,
        answers: answers,
        inHost: true,
      );

      await tester.tap(find.text('选项1释义'));
      await tester.pump();
      expect(answers[100], 0);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // isInitPart 免确认语义不变：已选答案仍写进共享答案表后直接退出
      expect(find.text('放弃本次作答？'), findsNothing);
      expect(find.text('打开答题'), findsOneWidget);
      expect(answers[100], 0);
    });

    testWidgets('原文视图系统返回 → 回题目视图且不弹确认（AppBar 返回同语义）', (tester) async {
      await _pumpQuiz(tester, height: 1200, preview: true, inHost: true);

      // 先选一个答案：若返回弹确认说明走了退出路径，直接暴露语义错误
      await tester.tap(find.text('选项1释义'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.article_outlined));
      await tester.pumpAndSettle();
      expect(find.textContaining('庆历四年春', findRichText: true), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // 只读原文不是路由级退出：系统返回回题目视图，不弹确认、不离开路由
      expect(find.text('放弃本次作答？'), findsNothing);
      expect(find.text('第 1/1 题'), findsOneWidget);
      expect(find.text('选项1释义'), findsOneWidget);
      expect(find.text('打开答题'), findsNothing);

      // AppBar 返回箭头与系统返回同语义：再看原文后点它，同样回题目
      await tester.tap(find.byIcon(Icons.article_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('放弃本次作答？'), findsNothing);
      expect(find.text('第 1/1 题'), findsOneWidget);
      expect(find.textContaining('庆历四年春', findRichText: true), findsNothing);
    });
  });
}
