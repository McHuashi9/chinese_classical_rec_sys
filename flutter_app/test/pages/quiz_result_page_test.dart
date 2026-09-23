import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/pages/quiz_result_page.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';

import '../helpers/quiz_test_support.dart';

/// 判分固定为“答错”，供结果页呈现类用例如需覆盖再子类化。
/// 判分行为由 `makeFakeQuizTracker()` 提供（与 quiz_page_test 同源）。
void main() {
  testWidgets('结果页展示全部选项并标记用户选择与正确答案', (tester) async {
    setQuizViewport(tester, height: 1200);
    final questions = fakeQuestions(1);
    writeQuestionStr(questions.first.ptr.ref.explanation, '正确答案：B。解析内容');
    final answers = [
      QuizAnswer(
        questionId: 100,
        selected: 0,
        correct: false,
        abilityBefore: List.filled(10, 0.5),
      ),
    ];

    final userCtrl = UserController();
    userCtrl.initTracker(FakeQuizTracker());
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);

    await tester.pumpWidget(wrapQuizPage(
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
    setQuizViewport(tester, height: 1200);
    final questions = fakeQuestions(1);
    // 真实数据格式：正确答案后跟选项文本，而不是字母。
    writeQuestionStr(questions.first.ptr.ref.explanation, '正确答案：选项3释义。解析内容');
    final answers = [
      QuizAnswer(
        questionId: 100,
        selected: 0,
        correct: false,
        abilityBefore: List.filled(10, 0.5),
      ),
    ];

    final userCtrl = UserController();
    userCtrl.initTracker(FakeQuizTracker());
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);

    await tester.pumpWidget(wrapQuizPage(
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
}
