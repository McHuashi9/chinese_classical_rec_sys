import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/engine/ffi_call.dart';

/// 可编排的 Fake：批量提交按预设用户/判分序列返回；[fail]=true 时抛 FFI 失败。
/// 内存契约：最终 user 所有权转移给 UserController。
class _ScriptedQuizTracker implements QuizTracker {
  /// 每题作答后的用户；最后一项为批量结果 user（所有权交给调用方）。
  final List<User> users = [];
  List<bool>? correctness;

  /// true 时批量 FFI 调用失败（模拟 C++ 事务失败/整批回滚）。
  bool fail = false;

  /// prune 返回值：null = 原样返回传入 user；非 null = 裁剪后的 user
  User? pruneResult;

  /// 记录最近一次批量提交的 isReview（复习通道断言用）
  bool lastIsReview = false;

  /// 批量 FFI 调用次数。
  int batchCalls = 0;

  /// getDueReviews 的替代实现（reviewCount 测试用）；null 走默认空列表
  List<ReviewItem> Function()? dueReviewOverride;

  /// getDueReviewCount 的替代实现（N15 方案 B 后 reviewCount 走 count 通道）；
  /// null 走默认 0
  int Function()? dueReviewCountOverride;

  /// getTotalReviewCount 的替代实现；null 走默认 0
  int Function()? totalReviewCountOverride;

  /// applyRead 的返回结果（阅读效应用例）；
  User? readResult;

  @override
  QuizBatchResult applyQuizBatch(
      User user, List<int> questionIds, List<int> choices,
      {bool isReview = false}) {
    batchCalls++;
    lastIsReview = isReview;
    if (fail || users.isEmpty) {
      throw const FfiException(
          operation: 'tracker_apply_quiz_batch', code: BridgeError.errGeneric);
    }
    final before = <List<double>>[];
    User cursor = user;
    for (int i = 0; i < questionIds.length; i++) {
      before.add([for (int d = 0; d < 10; d++) cursor.getAbility(d)]);
      cursor = users[i];
    }
    return QuizBatchResult(
      user: users.last,
      correct: correctness ?? List<bool>.filled(questionIds.length, true),
      abilityBefore: before,
    );
  }

  @override
  User applyRead(User user, int textId, double readTime) => readResult!;

  @override
  QuizBatch getQuestionsForText(int textId) => QuizBatch([]);

  @override
  List<ReviewItem> getDueReviews(int textId) => dueReviewOverride?.call() ?? [];

  @override
  int getDueReviewCount(int textId) => dueReviewCountOverride?.call() ?? 0;

  @override
  int getTotalReviewCount(int textId) => totalReviewCountOverride?.call() ?? 0;

  @override
  List<Question> getQuestionsByIds(List<int> ids) => [];

  @override
  QuizAttemptSummary? getAttemptSummary(int textId) => null;

  @override
  User prune(User user) => pruneResult ?? user;

  @override
  void disposeQuestions(List<Question> questions) {}
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

    test('批量 FFI 失败：抛异常，无任何生效，UI 可重试', () {
      final before = freshUser();
      tracker.fail = true;
      expect(
        () => ctrl.submitQuiz(questions(2), [0, 1]),
        throwsA(isA<FfiException>()),
      );
      expect(identical(ctrl.user, before), isTrue);
    });

    test('全对：逐题结果正确，用户指针替换为最终用户', () {
      final initial = freshUser();
      final u1 = User.allocate(calloc);
      final u2 = User.allocate(calloc);
      tracker.users.addAll([u1, u2]);
      tracker.correctness = [true, true];

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
      tracker.users.addAll([u1, u2]);
      tracker.correctness = [true, false];

      final answers = ctrl.submitQuiz(questions(2), [0, 1])!;

      for (int j = 0; j < 10; j++) {
        expect(answers[0].abilityBefore[j], 0.0);
        expect(answers[1].abilityBefore[j], 0.4);
      }
    });

    test('单次 FFI 批量提交：两题只调用一次 tracker', () {
      freshUser();
      tracker.users.addAll([User.allocate(calloc), User.allocate(calloc)]);

      ctrl.submitQuiz(questions(2), [0, 1]);

      expect(tracker.batchCalls, 1);
    });

    test('成功提交触发 notifyListeners 且每题结果齐全', () {
      freshUser();
      tracker.users.addAll([User.allocate(calloc), User.allocate(calloc)]);
      tracker.correctness = [true, false];

      var notified = 0;
      ctrl.addListener(() => notified++);
      final answers = ctrl.submitQuiz(questions(2), [0, 1]);

      expect(answers, isNotNull);
      expect(answers!.length, 2);
      expect(notified, 1);
    });

    test('提交成功后 prune 生效（与阅读链路一致，quiz 增量也被裁剪）', () {
      freshUser();
      tracker.users.addAll([User.allocate(calloc), User.allocate(calloc)]);
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

    test('批量事务成功后统一 prune 一次', () {
      freshUser();
      tracker.users.addAll([User.allocate(calloc), User.allocate(calloc)]);
      final pruned = User.allocate(calloc);
      tracker.pruneResult = pruned;

      final answers = ctrl.submitQuiz(questions(2), [0, 1]);

      expect(answers, isNotNull);
      expect(answers!.length, 2);
      expect(identical(ctrl.user, pruned), isTrue);
    });

    test('isReview 透传：复习提交逐题带 isReview=true', () {
      freshUser();
      tracker.users.addAll([User.allocate(calloc), User.allocate(calloc)]);

      final answers = ctrl.submitQuiz(questions(2), [0, 1], isReview: true);

      expect(answers, isNotNull);
      expect(tracker.lastIsReview, isTrue);
    });

    test('isReview 默认 false：正式测验不带复习标记', () {
      freshUser();
      tracker.users.add(User.allocate(calloc));

      ctrl.submitQuiz(questions(1), [0]);

      expect(tracker.lastIsReview, isFalse);
    });

    test('提交后 reviewCount 置脏重查（复习状态可能已变；走 count 通道）', () {
      freshUser();
      tracker.users.add(User.allocate(calloc));
      var reviewQueries = 0;
      tracker.dueReviewCountOverride = () {
        reviewQueries++;
        return 0;
      };

      expect(ctrl.reviewCount, 0); // 懒查第一次
      expect(reviewQueries, 1);
      ctrl.submitQuiz(questions(1), [0]);
      expect(ctrl.reviewCount, 0); // 提交后置脏 → 重查
      expect(reviewQueries, 2);
    });

    test('reviewCount 显示真实总数（不受列表上限影响）', () {
      freshUser();
      questions(1); // 分配 block 供 tearDown 统一释放（避免复用上一测试已释放指针）
      // 模拟到期 523 条（> 旧实现 500 上限）：count 通道返回真实数字
      tracker.dueReviewCountOverride = () => 523;
      expect(ctrl.reviewCount, 523);
    });

    test('totalReviewCount 懒查并随提交置脏重查', () {
      freshUser();
      tracker.users.add(User.allocate(calloc));
      var totalQueries = 0;
      tracker.totalReviewCountOverride = () {
        totalQueries++;
        return 7;
      };

      expect(ctrl.totalReviewCount, 7);
      expect(totalQueries, 1);
      ctrl.submitQuiz(questions(1), [0]);
      expect(ctrl.totalReviewCount, 7); // 提交后置脏 → 重查
      expect(totalQueries, 2);
    });
  });

  group('UserController.applyReadEffect', () {
    late UserController ctrl;
    late _ScriptedQuizTracker tracker;
    late User initial;
    late User updated;

    setUp(() {
      ctrl = UserController();
      tracker = _ScriptedQuizTracker();
      ctrl.initTracker(tracker);
      initial = User.allocate(calloc);
      updated = User.allocate(calloc);
      ctrl.setUser(initial);
      tracker.readResult = updated;
    });

    tearDown(() => ctrl.dispose());

    test('阅读成功后通知 UI 且用户指针更新', () {
      var notified = 0;
      ctrl.addListener(() => notified++);
      expect(ctrl.applyReadEffect(1, 60), isTrue);
      expect(identical(ctrl.user, updated), isTrue);
      expect(notified, 1);
    });
  });
}
