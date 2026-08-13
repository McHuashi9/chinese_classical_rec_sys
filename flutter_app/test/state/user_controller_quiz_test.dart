import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';

/// 可编排的 Fake：applyQuiz 按预设序列返回（null → 判题失败）
/// 内存契约：每次 applyQuiz 必须返回新分配的 User（submitQuiz 会 dispose）
class _ScriptedQuizTracker implements QuizTracker {
  final List<(User?, bool?)> results = [];

  /// prune 返回值：null = 不裁剪（直接采纳传入 user）；非 null = 裁剪后的 user
  User? pruneResult;

  /// 记录最近一次 applyQuiz 收到的 isReview（复习通道断言用）
  bool lastIsReview = false;

  /// getDueReviews 的替代实现（reviewCount 测试用）；null 走默认空列表
  List<ReviewItem> Function()? dueReviewOverride;

  @override
  (User?, bool?) applyQuiz(User user, int questionId, int choice,
      {bool isReview = false}) {
    lastIsReview = isReview;
    if (results.isEmpty) return (null, null);
    return results.removeAt(0);
  }

  @override
  User? applyRead(User user, int textId, double readTime) => null;

  @override
  void disposeQuestions(List<Question> questions) {}

  @override
  QuizBatch getQuestionsForText(int textId) => QuizBatch([]);

  @override
  List<ReviewItem> getDueReviews(int textId) =>
      dueReviewOverride?.call() ?? [];

  @override
  List<Question> getQuestionsByIds(List<int> ids) => [];

  @override
  QuizAttemptSummary? getAttemptSummary(int textId) => null;

  @override
  User? prune(User user) => pruneResult;
}

void main() {
  group('UserController.submitQuiz', () {
    late UserController ctrl;
    late _ScriptedQuizTracker tracker;
    late Pointer<QuestionData> block;

    setUp(() {
      ctrl = UserController();
      tracker = _ScriptedQuizTracker();
      ctrl.initTracker(tracker);
    });

    tearDown(() {
      ctrl.dispose();
      calloc.free(block);
    });

    /// 分配 N 题的整块内存，id 从 [startId] 递增
    List<Question> questions(int n, {int startId = 1}) {
      block = calloc<QuestionData>(n);
      for (int i = 0; i < n; i++) {
        (block + i).ref.id = startId + i;
      }
      return [for (int i = 0; i < n; i++) Question(block + i, owner: block)];
    }

    User? freshUser() {
      final u = User.allocate(calloc);
      ctrl.setUser(u);
      return u;
    }

    test('user 为 null 时返回 null', () {
      expect(ctrl.submitQuiz(questions(1), [0]), isNull);
    });

    test('题目数与选项数不匹配返回 null，用户不变', () {
      final before = freshUser();
      expect(ctrl.submitQuiz(questions(2), [0]), isNull);
      expect(identical(ctrl.user, before), isTrue);
    });

    test('首题判题失败：返回 null，无任何生效', () {
      final before = freshUser();
      tracker.results.add((null, null));
      expect(ctrl.submitQuiz(questions(2), [0, 1]), isNull);
      expect(identical(ctrl.user, before), isTrue);
    });

    test('全对：逐题结果正确，用户指针替换为最终用户', () {
      final initial = freshUser();
      final u1 = User.allocate(calloc);
      final u2 = User.allocate(calloc);
      tracker.results.addAll([(u1, true), (u2, true)]);

      final answers = ctrl.submitQuiz(questions(2), [0, 1]);

      expect(answers, isNotNull);
      expect(answers!.length, 2);
      expect(answers[0].questionId, 1);
      expect(answers[0].correct, isTrue);
      expect(answers[1].questionId, 2);
      expect(answers[1].correct, isTrue);
      expect(identical(ctrl.user, u2), isTrue);
      expect(identical(ctrl.user, initial), isFalse);
    });

    test('能力快照为每题答前能力（第 2 题快照 = 第 1 题答后）', () {
      freshUser();
      // 通过"每个返回的 User 带不同能力"模拟效应：
      // 第 1 题答前能力来自初始 user（全部 0.0），答后 user1（全部 0.4）
      final u1 = User.allocate(calloc);
      final u2 = User.allocate(calloc);
      for (int j = 0; j < 10; j++) {
        u1.ptr.ref.abilities[j] = 0.4;
      }
      for (int j = 0; j < 10; j++) {
        u2.ptr.ref.abilities[j] = 0.6;
      }
      tracker.results.addAll([(u1, true), (u2, false)]);

      final answers = ctrl.submitQuiz(questions(2), [0, 1])!;

      for (int j = 0; j < 10; j++) {
        expect(answers[0].abilityBefore[j], 0.0);
        expect(answers[1].abilityBefore[j], 0.4);
      }
    });

    test('第 2 题起判题失败：部分生效，内存态同步为已生效部分', () {
      freshUser();
      final u1 = User.allocate(calloc);
      for (int j = 0; j < 10; j++) {
        u1.ptr.ref.abilities[j] = 0.4;
      }
      tracker.results.addAll([(u1, true), (null, null)]);

      var notified = 0;
      ctrl.addListener(() => notified++);
      final answers = ctrl.submitQuiz(questions(2), [0, 1]);

      expect(answers, isNotNull);
      expect(answers!.length, 1);
      expect(answers[0].correct, isTrue);
      // 内存态 = 第 1 题答后用户（避免下次重复生效）
      expect(identical(ctrl.user, u1), isTrue);
      expect(notified, 1);
    });

    test('成功提交触发 notifyListeners 且每题结果齐全', () {
      freshUser();
      tracker.results.addAll([(User.allocate(calloc), true), (User.allocate(calloc), false)]);

      var notified = 0;
      ctrl.addListener(() => notified++);
      final answers = ctrl.submitQuiz(questions(2), [0, 1]);

      expect(answers, isNotNull);
      expect(answers!.length, 2);
      expect(notified, 1);
    });

    test('提交成功后 prune 生效（与阅读链路一致，quiz 增量也被裁剪）', () {
      freshUser();
      tracker.results.addAll([(User.allocate(calloc), true), (User.allocate(calloc), true)]);
      final pruned = User.allocate(calloc);
      tracker.pruneResult = pruned;

      var notified = 0;
      ctrl.addListener(() => notified++);
      final answers = ctrl.submitQuiz(questions(2), [0, 1]);

      expect(answers, isNotNull);
      expect(answers!.length, 2);
      // prune 返回非 null → 采纳裁剪后的 user（模拟增量被合并进基础能力）
      expect(identical(ctrl.user, pruned), isTrue);
      expect(notified, 1);
    });

    test('部分失败路径同样 prune（已生效部分与成功路径行为一致）', () {
      freshUser();
      tracker.results.addAll([(User.allocate(calloc), true), (null, null)]);
      final pruned = User.allocate(calloc);
      tracker.pruneResult = pruned;

      final answers = ctrl.submitQuiz(questions(2), [0, 1]);

      expect(answers, isNotNull);
      expect(answers!.length, 1);
      expect(identical(ctrl.user, pruned), isTrue);
    });

    test('isReview 透传：复习提交逐题带 isReview=true', () {
      freshUser();
      tracker.results.addAll([(User.allocate(calloc), true), (User.allocate(calloc), true)]);

      final answers = ctrl.submitQuiz(questions(2), [0, 1], isReview: true);

      expect(answers, isNotNull);
      expect(tracker.lastIsReview, isTrue);
    });

    test('isReview 默认 false：正式测验不带复习标记', () {
      freshUser();
      tracker.results.addAll([(User.allocate(calloc), true)]);

      ctrl.submitQuiz(questions(1), [0]);

      expect(tracker.lastIsReview, isFalse);
    });

    test('提交后 reviewCount 置脏重查（复习状态可能已变）', () {
      freshUser();
      tracker.results.addAll([(User.allocate(calloc), true)]);
      var reviewQueries = 0;
      tracker.dueReviewOverride = () {
        reviewQueries++;
        return [];
      };

      expect(ctrl.reviewCount, 0); // 懒查第一次
      expect(reviewQueries, 1);
      ctrl.submitQuiz(questions(1), [0]);
      expect(ctrl.reviewCount, 0); // 提交后置脏 → 重查
      expect(reviewQueries, 2);
    });
  });
}
