import 'dart:convert';
import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 答题相关 widget 测试的公共脚手架。
///
/// 只收模板化、与断言语义无关的部分：视口尺寸、伪题目内存块、
/// provider/主题包装。业务 fake（tracker/coordinator 子类）留在各自用例文件，
/// 避免把测试语义藏进共享文件。

/// 固定答题页测试视口（逻辑尺寸 [width]×[height]），退出时自动复位。
///
/// 用 `addTearDown` 而非 try/finally：用例失败时同样复位，不污染后续用例。
void setQuizViewport(WidgetTester tester,
    {double width = 800, double height = 1000}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// 构造 [n] 道伪题目的 FFI 内存块，并登记 [Question] 列表。
///
/// 调用方拿到列表后**无需**自己 `calloc.free`：owner 的释放已挂到
/// `addTearDown`（题目内存所有权恰好释放一次是用例断言点，故必须自动收尾）。
List<Question> fakeQuestions(int n, {int textId = 1}) {
  final block = calloc<QuestionData>(n);
  for (int i = 0; i < n; i++) {
    final q = (block + i).ref;
    q.id = 100 + i;
    q.textId = textId;
    writeQuestionStr(q.qType, 'shici');
    writeQuestionStr(q.stem, '第${i + 1}题题干：加点词解释');
    for (int k = 0; k < 4; k++) {
      // options 为扁平 2048 字节（与 C++ char[4][512] 布局一致），按 512 偏移写
      writeQuestionStr(q.options, '选项${k + 1}释义', offset: k * 512);
    }
    writeQuestionStr(q.dims, '3,4,9');
    writeQuestionStr(q.explanation, '第${i + 1}题解析');
    q.difficulty = 0.5;
  }
  final questions = [
    for (int i = 0; i < n; i++) Question(block + i, owner: block),
  ];
  addTearDown(() => calloc.free(block));
  return questions;
}

/// 向 FFI 定长 `char[512]` 字段写入 UTF-8 字符串（超出即截断，末尾补 0）。
void writeQuestionStr(Array<Uint8> arr, String s, {int offset = 0}) {
  final bytes = utf8.encode(s);
  for (int i = 0; i < bytes.length && i < 512; i++) {
    arr[offset + i] = bytes[i];
  }
  arr[offset + bytes.length] = 0;
}

/// 在 TextSpan 树里找带下划线样式的目标词 span。
TextStyle? findUnderlinedMark(InlineSpan span, String word) {
  if (span is TextSpan) {
    if (span.text == word &&
        span.style?.decoration == TextDecoration.underline) {
      return span.style;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      final hit = findUnderlinedMark(child, word);
      if (hit != null) return hit;
    }
  }
  return null;
}

/// 用答题页所需的 provider/主题包装 [child]，未传入的控制器就地新建。
///
/// `AppCoordinator` 必须显式提供：`QuizPage._submit` 读取 `syncing` 同步闸门。
Widget wrapQuizPage(
  Widget child, {
  AppCoordinator? coord,
  SettingsController? settingsCtrl,
  UserController? userCtrl,
}) {
  final sCtrl = settingsCtrl ?? SettingsController();
  final uCtrl = userCtrl ?? UserController();
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

/// 模拟成功判分的 tracker：走真实 [UserController.submitQuiz]，只替换 C++ 判题。
///
/// 默认第 1 题判对、其余判错（覆盖“答错入复习队列”一类断言）；
/// 需要其他判分序列时子类化并覆写 [applyQuiz]。
class FakeQuizTracker implements QuizTracker {
  FakeQuizTracker();

  int _calls = 0;

  /// 第 N 次起判题失败（0 表示全成功）。
  int failFrom = 0;

  /// [disposeQuestions] 调用次数（验证题目内存恰好释放一次）。
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
