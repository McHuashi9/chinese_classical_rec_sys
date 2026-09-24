// 集成测试（真实 .so + 资产库 + 真实 AppCoordinator）：覆盖做题页方案 D 的
// 「进入做题页 → 页内切到原文 → 切回 → 退出」整条路径。
//
// 为什么单独建文件：quiz_page_test.dart 走的是假题目 + 假 coordinator，
// 覆盖不到真实 FFI 取题、真实 getTextDetail 读全文、真实 ReadingController
// 会话这三处；而线上出问题的恰恰是这一段。
//
// 依赖：需先构建核心（`cmake --build build --target chinese_core`）。
// 未找到 .so 或 python3 时自动跳过，不挂非 Linux 的 CI。
import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/pages/quiz_page.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

void main() {
  final lib = _tryLoadLibrary();
  final fixtureOk = _pythonAvailable();

  testWidgets('真实库：进做题页切原文再切回，只读且不结算阅读会话', (tester) async {
    if (lib == null) {
      markTestSkipped(
          '未找到 libchinese_core.so，先执行 cmake --build build --target chinese_core');
      return;
    }
    if (!fixtureOk) {
      markTestSkipped('未找到 python3，无法生成纯内容 fixture');
      return;
    }

    // 固定视口：正文分页需要真实尺寸
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({});

    final work = Directory.systemTemp.createTempSync('quiz_original_it');
    final contentDb = '${work.path}/classical.db';
    final userDb = '${work.path}/user.db';
    _makeContentFixture(contentDb);

    final readTracker = ReadTracker();
    final settingsCtrl = SettingsController();
    final readingCtrl = ReadingController(readTracker);
    final userCtrl = UserController();
    final coord = AppCoordinator(
      navCtrl: NavigationController(),
      settingsCtrl: settingsCtrl,
      readingCtrl: readingCtrl,
      userCtrl: userCtrl,
      readTracker: readTracker,
    );
    addTearDown(() {
      readingCtrl.pauseTimer();
      coord.dispose();
      try {
        work.deleteSync(recursive: true);
      } catch (_) {}
    });

    expect(await coord.init(contentDb, userDb, lib), isTrue,
        reason: '真实引擎 + fixture 内容库应能打开');

    // fixture 库没有已初始化档案，而 question_get_by_text 要求用户已初始化
    // （requireInitialized → BRIDGE_ERR_INIT_INCOMPLETE），否则取题恒为空。
    _initDefaultProfile(coord.bridge!);
    // UserController 的初始化状态是 coord.init 期间缓存的，引擎侧补初始化后需刷新
    coord.userCtrl.refreshInitState();
    expect(coord.userCtrl.isInitialized, isTrue);

    // 挑一篇真有题目的文章，并拿到真实题目内存块（owner 由 QuizPage 释放）
    final text = _firstTextWithQuestions(coord);
    expect(text, isNotNull, reason: '资产库应至少有一篇带题文章');
    final questions = coord.userCtrl.getQuizQuestions(text!.id).questions;
    expect(questions, isNotEmpty);

    // 注意：coord.texts 里是轻量缓存条目（content 为空），正文必须经
    // getTextDetail 从内容库读——这正是假数据单测覆盖不到的一段。
    final detail = coord.getTextDetail(text.id);
    expect(detail, isNotNull);
    expect(detail!.content, isNotEmpty, reason: 'getTextDetail 应返回真实正文');

    // 打开活动阅读会话：从阅读进入做题的生产路径
    expect(coord.loadTextForReading(text.id), isTrue);
    expect(readingCtrl.isReading, isTrue);

    await tester.pumpWidget(_wrap(
      QuizPage(
        articleTitle: text.title,
        questions: questions,
        readingController: readingCtrl,
      ),
      coord: coord,
      settingsCtrl: settingsCtrl,
      userCtrl: userCtrl,
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2)); // 会话计时器走两拍

    expect(find.text('第 1/${questions.length} 题'), findsOneWidget);
    final elapsedBefore = readingCtrl.elapsedSeconds;
    expect(elapsedBefore, greaterThan(0));

    // ── 切到原文：真实 getTextDetail 读全文 + 真实分页 ──────────────────────
    await tester.tap(find.byTooltip('查看原文'));
    await tester.pumpAndSettle();

    // 回答页已翻到原文视图，且仍是同一个路由（方案 D 折叠路由的关键断言）
    expect(find.text('第 1/${questions.length} 题'), findsNothing);
    expect(find.byType(QuizPage), findsOneWidget);

    // 真实正文渲染：取文章开头一段做锚点。
    // 用 12 字而非 4 字——短锚点会跨多行/多 widget 命中；首页必然包含段首。
    expect(detail.content.runes.length, greaterThan(12), reason: '锚点需要足够长的正文');
    final head = String.fromCharCodes(detail.content.runes.take(12));
    expect(find.textContaining(head, findRichText: true), findsWidgets,
        reason: '原文视图应渲染真实正文开头：$head');

    // 只读语义：底部只有“返回”，没有完成/放弃
    expect(find.text('完成阅读'), findsNothing);
    expect(find.text('放弃'), findsNothing);

    // 活动会话复用同一控制器 → 计时连续
    await tester.pump(const Duration(seconds: 2));
    expect(readingCtrl.elapsedSeconds, greaterThan(elapsedBefore));

    // ── 切回题目：仍在同一路由，会话未结算 ────────────────────────────────
    await tester.tap(find.byTooltip('返回题目'));
    await tester.pumpAndSettle();
    expect(find.text('第 1/${questions.length} 题'), findsOneWidget);
    expect(readingCtrl.isReading, isTrue, reason: '切视图不是退出，阅读会话应保留');

    // 活动会话的周期计时器须在测试体内停掉：框架在 body 结束时就检查
    // pending timer，早于 addTearDown。
    readingCtrl.pauseTimer();
  });
}

/// 用答题页所需的 provider/主题包装被测页面。
Widget _wrap(
  Widget child, {
  required AppCoordinator coord,
  required SettingsController settingsCtrl,
  required UserController userCtrl,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settingsCtrl),
      ChangeNotifierProvider.value(value: userCtrl),
      Provider.value(value: coord),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme(ScreenSize.medium, 1.0,
          accentColor: AppTheme.vermilion),
      home: child,
    ),
  );
}

/// 找第一篇能取到题目的文章（资产库中并非每篇都有题）。
ChineseText? _firstTextWithQuestions(AppCoordinator coord) {
  for (final t in coord.texts.take(40)) {
    final batch = coord.userCtrl.getQuizQuestions(t.id);
    if (batch.questions.isNotEmpty) {
      coord.userCtrl.disposeQuizQuestions(batch.questions);
      return t;
    }
  }
  return null;
}

// ─── helpers（与 engine_chain_test 同源；测试辅助允许少量重复）──────────────

DynamicLibrary? _tryLoadLibrary() {
  for (final p in [
    '../build/libchinese_core.so',
    '../build/tests/libchinese_core.so',
    'build/libchinese_core.so',
  ]) {
    final f = File(p);
    if (f.existsSync()) return DynamicLibrary.open(f.absolute.path);
  }
  return null;
}

bool _pythonAvailable() {
  try {
    return Process.runSync('python3', ['--version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

String _assetDbPath() {
  for (final p in [
    'assets/data/classical.db',
    '../flutter_app/assets/data/classical.db',
  ]) {
    if (File(p).existsSync()) return p;
  }
  throw StateError('找不到资产 DB（assets/data/classical.db）');
}

String _fixtureScriptPath() {
  for (final p in [
    'test/helpers/make_content_fixture.py',
    '../flutter_app/test/helpers/make_content_fixture.py',
  ]) {
    if (File(p).existsSync()) return p;
  }
  throw StateError('找不到 make_content_fixture.py');
}

/// 完成默认档案强制初始化（初始化题统一选 0）。已初始化时跳过。
void _initDefaultProfile(NativeBridge b) {
  if (b.userIsInitialized() > 0) return;
  final block = calloc<QuestionData>(8);
  final n = b.userInitQuestions(block, 8);
  if (n <= 0) {
    calloc.free(block);
    throw StateError('无法获取初始化题');
  }
  final qids = calloc<Int32>(n);
  final choices = calloc<Int32>(n);
  for (int i = 0; i < n; i++) {
    qids[i] = (block + i).ref.id;
    choices[i] = 0;
  }
  final out = calloc<UserData>();
  final rc = b.userInitApply(qids, choices, n, 1700000000, out);
  calloc.free(qids);
  calloc.free(choices);
  calloc.free(out);
  calloc.free(block);
  if (rc != BridgeError.ok) {
    throw StateError('初始化默认档案失败 rc=$rc');
  }
}

/// 生成纯内容库 fixture（剔除用户表），供 dbOpen 使用。
void _makeContentFixture(String dest) {
  final result =
      Process.runSync('python3', [_fixtureScriptPath(), _assetDbPath(), dest]);
  if (result.exitCode != 0) {
    throw StateError('生成纯内容 fixture 失败: ${result.stderr}');
  }
}
