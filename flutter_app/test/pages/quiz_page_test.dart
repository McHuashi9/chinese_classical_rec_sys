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
import 'package:chinese_classical_rec_sys/pages/quiz_page.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';

Widget _wrap(Widget child) {
  final settingsCtrl = SettingsController();
  final userCtrl = UserController(ReadTracker());
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settingsCtrl),
      ChangeNotifierProvider.value(value: userCtrl),
    ],
    child: MaterialApp(home: child),
  );
}

/// 模拟成功判分的控制器（成功提交链路测试用）
class _FakeSubmitUserController extends UserController {
  _FakeSubmitUserController() : super(ReadTracker());

  @override
  List<QuizAnswer>? submitQuiz(List<Question> questions, List<int> choices) {
    return [
      for (int i = 0; i < questions.length; i++)
        QuizAnswer(
          questionId: questions[i].id,
          selected: choices[i],
          correct: i == 0, // 第 1 题对、其余错
          abilityBefore: List.filled(10, 0.3),
        ),
    ];
  }

  // 释放交给测试管理（结果页 dispose 时会调用，这里置空避免提前 free）
  @override
  void disposeQuizQuestions(List<Question> questions) {}
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
    // 末题未答：提交禁用
    final submitBtn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(submitBtn.onPressed, isNull);

    // 答完末题 → 提交可用
    await tester.tap(find.text('选项1释义'));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);

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
    final userCtrl = _FakeSubmitUserController();
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
  });
}