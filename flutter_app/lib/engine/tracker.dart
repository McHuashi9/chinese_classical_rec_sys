import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';

import 'ffi_call.dart';

/// 单个题目作答结果（判分后）
class QuizAnswer {
  final int questionId;
  final int selected; // 用户选项 0-3
  final bool correct; // C++ 判定结果
  final List<double> abilityBefore; // 该题作答前 10 维能力

  QuizAnswer({
    required this.questionId,
    required this.selected,
    required this.correct,
    required this.abilityBefore,
  });
}

/// 单次批量 FFI 调用的完整结果。只有 C++ 事务提交成功后才会构造本对象。
class QuizBatchResult {
  /// 更新后的用户（所有权归调用方，由 UserController 接管并最终释放）。
  final User user;

  /// 与输入题组同序的判题结果。
  final List<bool> correct;

  /// 与输入题组同序的作答前 10 维能力快照。
  final List<List<double>> abilityBefore;

  const QuizBatchResult({
    required this.user,
    required this.correct,
    required this.abilityBefore,
  });
}

/// 取题结果：题组 + 该篇是否已答完
class QuizBatch {
  final List<Question> questions;

  /// 该篇有题且全部答完（无题时为 false；用 questions.isEmpty 区分）
  final bool answeredAll;

  QuizBatch(this.questions, {this.answeredAll = false});

  bool get isEmpty => questions.isEmpty;
}

/// 到期错题条目（复习队列）
class ReviewItem {
  final int questionId;
  final int textId;
  final int correctStreak;
  final int wrongCount;
  final int nextReviewAt; // Unix 秒

  ReviewItem({
    required this.questionId,
    required this.textId,
    required this.correctStreak,
    required this.wrongCount,
    required this.nextReviewAt,
  });
}

/// 文章测验摘要
class QuizAttemptSummary {
  final int total;
  final int answered;
  final int wrong;

  const QuizAttemptSummary(this.total, this.answered, this.wrong);
}

/// 知识追踪能力抽象：UserController 依赖此接口（生产注入 KnowledgeTracker，
/// 测试注入 Fake）——FFI 依赖链（NativeBridge→DynamicLibrary）无法在单测中构造。
///
/// 失败契约：任何 FFI 负返回码都抛 [FfiException]（由引擎层统一记日志）；
/// `null` 只用于显式的业务“不存在”，空列表/0 只表示成功但无数据。
abstract class QuizTracker {
  /// 记录阅读事件，返回更新后的用户。FFI 失败抛 [FfiException]。
  User applyRead(User user, int textId, double readTime);

  /// 清理过期增量，返回更新后的用户。FFI 失败抛 [FfiException]。
  User prune(User user);

  /// 取该篇文章的题组（整块内存，用后由调用方 disposeQuestions 释放）
  QuizBatch getQuestionsForText(int textId);

  /// 释放 [getQuestionsForText]/[getQuestionsByIds] 返回的题组内存（恰好一次）
  void disposeQuestions(List<Question> questions);

  /// 到期错题列表（textId=0 取全部）；空列表仅表示成功但无到期条目。
  List<ReviewItem> getDueReviews(int textId);

  /// 到期错题总数（textId=0 取全部）：COUNT 聚合，不受列表上限截断
  int getDueReviewCount(int textId);

  /// 错题总数（textId=0 取全部；含未到期）：COUNT 聚合，不受列表上限截断
  int getTotalReviewCount(int textId);

  /// 按 id 取题（复习通道，不受"排除已答"影响）
  List<Question> getQuestionsByIds(List<int> ids);

  /// 文章测验摘要；null 仅表示文章不存在（BRIDGE_ERR_TEXT），其他失败抛异常。
  QuizAttemptSummary? getAttemptSummary(int textId);

  /// 批量答题：单次 FFI 调用内完成判分、能力效应、作答流水与复习状态。
  /// [isReview] = 错题复习：判题 + 写复习状态，但不产生答题效应。
  /// 失败必须抛 [FfiException]，且 C++ 事务保证整批回滚。
  QuizBatchResult applyQuizBatch(
      User user, List<int> questionIds, List<int> choices,
      {bool isReview = false});
}

/// 知识追踪 FFI 封装
class KnowledgeTracker implements QuizTracker {
  final NativeBridge _bridge;
  static const int quizBatchSize = 5;

  KnowledgeTracker(this._bridge);

  /// 记录阅读事件，更新用户能力
  /// [readTime] 阅读时长(秒)；是否触发由 C++ 按本文最低阅读时间判定
  @override
  User applyRead(User user, int textId, double readTime) {
    final outUser = User.allocate(calloc);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rc = _bridge.trackerApplyRead(
        user.ptr, textId, readTime, now, outUser.ptr, 0);
    if (rc != BridgeError.ok) {
      outUser.dispose();
      requireBridgeOk(rc, 'tracker_apply_read');
    }
    return outUser;
  }

  /// 清理过期增量，返回更新后的用户。失败抛 [FfiException]。
  @override
  User prune(User user) {
    final outUser = User.allocate(calloc);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rc = _bridge.trackerPrune(user.ptr, now, outUser.ptr);
    if (rc != BridgeError.ok) {
      outUser.dispose();
      requireBridgeOk(rc, 'tracker_prune');
    }
    return outUser;
  }

  /// 取该篇文章的题目（最多 [quizBatchSize] 题；排除已答含复习记录，
  /// 剩余随机轮换）。answeredAll 区分"无题"与"已答完"。
  /// 返回的题组为整块分配内存，用完调用 [disposeQuestions] 统一释放。
  /// 失败抛 [FfiException]；空题组仅表示成功但无题/已答完。
  @override
  QuizBatch getQuestionsForText(int textId) {
    const max = quizBatchSize;
    final block = calloc<QuestionData>(max);
    final answeredAllPtr = calloc<Int32>();
    final count = _bridge.questionGetByText(textId, block, max, answeredAllPtr);
    final answeredAll = answeredAllPtr.value != 0;
    calloc.free(answeredAllPtr);
    if (count < 0) {
      calloc.free(block);
      requireBridgeCount(count, 'question_get_by_text');
    }
    final actual = count > max ? max : count;
    if (actual == 0) {
      calloc.free(block);
      return QuizBatch([], answeredAll: answeredAll);
    }
    return QuizBatch(
      [for (int i = 0; i < actual; i++) Question(block + i, owner: block)],
      answeredAll: answeredAll,
    );
  }

  /// 释放 [getQuestionsForText]/[getQuestionsByIds] 返回的题组内存
  /// 注意：必须恰好调用一次（所有权单一归属），重复释放同一题组会导致 double free
  @override
  void disposeQuestions(List<Question> questions) {
    if (questions.isEmpty) return;
    calloc.free(questions.first.owner);
  }

  /// 到期错题列表（textId=0 全部），按到期时间升序。
  /// cap 为明细展示上限：超出部分不在此列出（总数请用 [getDueReviewCount]，
  /// 徽标等场景不要拿本列表长度冒充总数）。失败抛 [FfiException]。
  @override
  List<ReviewItem> getDueReviews(int textId) {
    const cap = 500;
    final block = calloc<ReviewItemData>(cap);
    final n = _bridge.quizGetReviewItems(textId, block, cap);
    if (n < 0) {
      calloc.free(block);
      requireBridgeCount(n, 'quiz_get_review_items');
    }
    final count = n > cap ? cap : n;
    final items = [
      for (int i = 0; i < count; i++)
        ReviewItem(
          questionId: (block + i).ref.questionId,
          textId: (block + i).ref.textId,
          correctStreak: (block + i).ref.correctStreak,
          wrongCount: (block + i).ref.wrongCount,
          nextReviewAt: (block + i).ref.nextReviewAt,
        ),
    ];
    calloc.free(block);
    return items;
  }

  /// 到期错题总数：COUNT 聚合通道，无 500 上限（N15 方案 B）。
  /// 失败抛 [FfiException]；0 仅表示成功且无到期错题。
  @override
  int getDueReviewCount(int textId) {
    final n = _bridge.quizGetDueReviewCount(textId);
    if (n < 0) requireBridgeCount(n, 'quiz_get_due_review_count');
    return n;
  }

  /// 错题总数：COUNT 聚合通道，含未到期，无 500 上限。
  /// 失败抛 [FfiException]；0 仅表示成功且无错题。
  @override
  int getTotalReviewCount(int textId) {
    final n = _bridge.quizGetReviewCount(textId);
    if (n < 0) requireBridgeCount(n, 'quiz_get_review_count');
    return n;
  }

  /// 按 id 取题（复习通道），缺失 id 被跳过；空列表仅表示成功但无题。
  @override
  List<Question> getQuestionsByIds(List<int> ids) {
    if (ids.isEmpty) return [];
    final idsPtr = calloc<Int32>(ids.length);
    for (int i = 0; i < ids.length; i++) {
      idsPtr[i] = ids[i];
    }
    final block = calloc<QuestionData>(ids.length);
    final n =
        _bridge.quizGetQuestionsByIds(idsPtr, ids.length, block, ids.length);
    calloc.free(idsPtr);
    if (n < 0) {
      calloc.free(block);
      requireBridgeCount(n, 'quiz_get_questions_by_ids');
    }
    final count = n > ids.length ? ids.length : n;
    if (count == 0) {
      calloc.free(block);
      return [];
    }
    return [
      for (int i = 0; i < count; i++) Question(block + i, owner: block),
    ];
  }

  /// 文章测验摘要；文章不存在返回 null（显式业务空态），其他失败抛异常。
  @override
  QuizAttemptSummary? getAttemptSummary(int textId) {
    final total = calloc<Int32>();
    final answered = calloc<Int32>();
    final wrong = calloc<Int32>();
    final rc = _bridge.quizGetAttemptSummary(textId, total, answered, wrong);
    if (rc != BridgeError.ok) {
      calloc.free(total);
      calloc.free(answered);
      calloc.free(wrong);
      if (rc == BridgeError.errText) return null;
      requireBridgeOk(rc, 'quiz_get_attempt_summary');
    }
    final summary =
        QuizAttemptSummary(total.value, answered.value, wrong.value);
    calloc.free(total);
    calloc.free(answered);
    calloc.free(wrong);
    return summary;
  }

  /// 批量答题：只调用一次 tracker_apply_quiz_batch。
  /// C++ 在一个事务内完成所有题目；失败整批回滚并抛 [FfiException]。
  @override
  QuizBatchResult applyQuizBatch(
      User user, List<int> questionIds, List<int> choices,
      {bool isReview = false}) {
    if (questionIds.length != choices.length || questionIds.isEmpty) {
      throw ArgumentError('questionIds 与 choices 必须等长且非空');
    }
    final idsPtr = calloc<Int32>(questionIds.length);
    final choicesPtr = calloc<Int32>(choices.length);
    final outUser = User.allocate(calloc);
    final outCorrect = calloc<Int32>(questionIds.length);
    final outAbilityBefore = calloc<Double>(questionIds.length * 10);
    for (int i = 0; i < questionIds.length; i++) {
      idsPtr[i] = questionIds[i];
      choicesPtr[i] = choices[i];
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rc = _bridge.trackerApplyQuizBatch(
      user.ptr,
      idsPtr,
      choicesPtr,
      questionIds.length,
      now,
      outUser.ptr,
      outCorrect,
      outAbilityBefore,
      isReview ? 1 : 0,
    );
    calloc.free(idsPtr);
    calloc.free(choicesPtr);
    if (rc != BridgeError.ok) {
      calloc.free(outCorrect);
      calloc.free(outAbilityBefore);
      outUser.dispose();
      requireBridgeOk(rc, 'tracker_apply_quiz_batch');
    }
    final correct = <bool>[
      for (int i = 0; i < questionIds.length; i++) outCorrect[i] != 0,
    ];
    final abilityBefore = <List<double>>[
      for (int i = 0; i < questionIds.length; i++)
        [for (int d = 0; d < 10; d++) outAbilityBefore[i * 10 + d]],
    ];
    calloc.free(outCorrect);
    calloc.free(outAbilityBefore);
    return QuizBatchResult(
      user: outUser,
      correct: correct,
      abilityBefore: abilityBefore,
    );
  }
}
