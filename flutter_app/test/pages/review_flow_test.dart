import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/pages/review_list_page.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';

class _FakeCoordinator extends AppCoordinator {
  _FakeCoordinator({
    required super.navCtrl,
    required super.settingsCtrl,
    required super.readingCtrl,
    required super.userCtrl,
    required super.readTracker,
  });

  final List<ChineseText> fakeTexts = [
    ChineseText(
      id: 1,
      title: '岳阳楼记',
      author: '范仲淹',
      dynasty: '宋',
      source: '古文观止',
      background: '',
      content: '',
      charCount: 300,
      difficulties: List.filled(10, 0.5),
    ),
  ];

  @override
  List<ChineseText> get texts => fakeTexts;
}

class _FakeReviewTracker implements QuizTracker {
  final List<ReviewItem> due;
  List<Question> byIdsResult = [];
  int byIdsCalls = 0;
  int disposedCount = 0;

  _FakeReviewTracker(this.due);

  @override
  (User?, bool?) applyQuiz(User user, int questionId, int choice,
          {bool isReview = false}) =>
      (User.allocate(calloc), true);

  @override
  User? applyRead(User user, int textId, double readTime) => null;

  @override
  User? prune(User user) => null;

  @override
  QuizBatch getQuestionsForText(int textId) => QuizBatch([]);

  @override
  List<ReviewItem> getDueReviews(int textId) =>
      textId == 0 ? due : due.where((r) => r.textId == textId).toList();

  @override
  List<Question> getQuestionsByIds(List<int> ids) {
    byIdsCalls++;
    return byIdsResult;
  }

  @override
  QuizAttemptSummary? getAttemptSummary(int textId) => null;

  @override
  void disposeQuestions(List<Question> questions) {
    disposedCount++;
  }
}

void main() {
  testWidgets('ReviewListPage 按篇分组展示到期错题，点组进入复习答题页', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final navCtrl = NavigationController();
    final settingsCtrl = SettingsController();
    final readingCtrl = ReadingController(ReadTracker());
    final userCtrl = UserController();
    final tracker = _FakeReviewTracker([
      ReviewItem(
          questionId: 11, textId: 1, correctStreak: 0, wrongCount: 1, nextReviewAt: 0),
      ReviewItem(
          questionId: 12, textId: 1, correctStreak: 1, wrongCount: 2, nextReviewAt: 0),
    ]);
    // 复习取题通道返回两题（内存块由页面链释放）
    final block = calloc<QuestionData>(2);
    (block).ref.id = 11;
    (block + 1).ref.id = 12;
    tracker.byIdsResult = [
      Question(block, owner: block),
      Question(block + 1, owner: block),
    ];
    userCtrl.initTracker(tracker);
    userCtrl.setUser(User.allocate(calloc));
    addTearDown(userCtrl.dispose);
    final coord = _FakeCoordinator(
      navCtrl: navCtrl,
      settingsCtrl: settingsCtrl,
      readingCtrl: readingCtrl,
      userCtrl: userCtrl,
      readTracker: ReadTracker(),
    );

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsCtrl),
        ChangeNotifierProvider<UserController>.value(value: userCtrl),
        Provider<AppCoordinator>.value(value: coord),
      ],
      child: const MaterialApp(home: ReviewListPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('错题复习'), findsOneWidget);
    expect(find.text('岳阳楼记'), findsOneWidget);
    expect(find.text('2 道错题到期'), findsOneWidget);

    // 点组 → getQuestionsByIds 取题 → 复习答题页
    await tester.tap(find.text('岳阳楼记'));
    await tester.pumpAndSettle();
    expect(tracker.byIdsCalls, 1);
    expect(find.textContaining('错题复习 · 岳阳楼记'), findsOneWidget);

    // 拆树：题组内存恰好释放一次（QuizPage 未提交 → 自身 dispose 释放）
    await tester.pumpWidget(const SizedBox());
    expect(tracker.disposedCount, 1);
  });

  testWidgets('ReviewListPage 无到期错题显示空态', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final navCtrl = NavigationController();
    final settingsCtrl = SettingsController();
    final readingCtrl = ReadingController(ReadTracker());
    final userCtrl = UserController();
    userCtrl.initTracker(_FakeReviewTracker([]));
    final coord = _FakeCoordinator(
      navCtrl: navCtrl,
      settingsCtrl: settingsCtrl,
      readingCtrl: readingCtrl,
      userCtrl: userCtrl,
      readTracker: ReadTracker(),
    );

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsCtrl),
        ChangeNotifierProvider<UserController>.value(value: userCtrl),
        Provider<AppCoordinator>.value(value: coord),
      ],
      child: const MaterialApp(home: ReviewListPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('暂无到期错题'), findsOneWidget);
  });
}
