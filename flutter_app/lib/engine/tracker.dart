import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';

/// 单个题目作答结果（判分后）
class QuizAnswer {
  final int questionId;
  final int selected;   // 用户选项 0-3
  final bool correct;   // C++ 判定结果
  final List<double> abilityBefore; // 该题作答前 10 维能力

  QuizAnswer({
    required this.questionId,
    required this.selected,
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
abstract class QuizTracker {
  /// 记录阅读事件，返回更新后的用户或 null（阅读时间不足）
  User? applyRead(User user, int textId, double readTime);

  /// 清理过期增量，返回更新后的用户
  User? prune(User user);

  /// 取该篇文章的题组（整块内存，用后由调用方 disposeQuestions 释放）
  QuizBatch getQuestionsForText(int textId);

  /// 释放 [getQuestionsForText]/[getQuestionsByIds] 返回的题组内存（恰好一次）
  void disposeQuestions(List<Question> questions);

  /// 到期错题列表（textId=0 取全部）
  List<ReviewItem> getDueReviews(int textId);

  /// 到期错题总数（textId=0 取全部）：COUNT 聚合，不受列表上限截断
  /// （徽标等"只要数字"的场景用，避免拿截断后的明细长度冒充总数）
  int getDueReviewCount(int textId);

  /// 错题总数（textId=0 取全部；含未到期）：COUNT 聚合，不受列表上限截断
  int getTotalReviewCount(int textId);

  /// 按 id 取题（复习通道，不受"排除已答"影响）
  List<Question> getQuestionsByIds(List<int> ids);

  /// 文章测验摘要（总题数/已答/错题数）；文章不存在或失败返回 null
  QuizAttemptSummary? getAttemptSummary(int textId);

  /// 答题：判题并更新能力，返回（更新后用户, 判定结果）。
  /// [isReview] = 错题复习：判题 + 写复习状态，但不产生答题效应。
  /// 内存契约：失败必须成对返回 (null, null)；成功必须返回新分配的 User
  /// （所有权转移给调用方，由调用方 dispose）。
  (User?, bool?) applyQuiz(User user, int questionId, int choice,
      {bool isReview = false});
}

/// 知识追踪 FFI 封装
class KnowledgeTracker implements QuizTracker {
  final NativeBridge _bridge;
  static const int quizBatchSize = 5;

  KnowledgeTracker(this._bridge);

  /// 记录阅读事件，更新用户能力
  /// [readTime] 阅读时长(秒)；是否触发由 C++ 按本文最低阅读时间判定
  /// 返回更新后的用户或 null (读取时间不足)
  @override
  User? applyRead(User user, int textId, double readTime) {
    final outUser = User.allocate(calloc);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rc = _bridge.trackerApplyRead(
        user.ptr, textId, readTime, now, outUser.ptr, 0);
    if (rc != BridgeError.ok) {
      outUser.dispose();
      return null;
    }
    return outUser;
  }

  /// 清理过期增量，返回更新后的用户
  @override
  User? prune(User user) {
    final outUser = User.allocate(calloc);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rc = _bridge.trackerPrune(user.ptr, now, outUser.ptr);
    if (rc != BridgeError.ok) {
      outUser.dispose();
      return null;
    }
    return outUser;
  }

  /// 取该篇文章的题目（最多 [quizBatchSize] 题；排除已答含复习记录，
  /// 剩余随机轮换）。answeredAll 区分"无题"与"已答完"。
  /// 返回的题组为整块分配内存，用完调用 [disposeQuestions] 统一释放。
  /// 注意：count<0（如 BRIDGE_ERR_TEXT 文章不存在）与 0（无题）统一按空返回。
  @override
  QuizBatch getQuestionsForText(int textId) {
    const max = quizBatchSize;
    final block = calloc<QuestionData>(max);
    final answeredAllPtr = calloc<Int32>();
    final count = _bridge.questionGetByText(textId, block, max, answeredAllPtr);
    final answeredAll = answeredAllPtr.value != 0;
    calloc.free(answeredAllPtr);
    if (count <= 0) {
      calloc.free(block);
      return QuizBatch([], answeredAll: answeredAll);
    }
    return QuizBatch(
      [for (int i = 0; i < count; i++) Question(block + i, owner: block)],
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
  /// 徽标等场景不要拿本列表长度冒充总数）
  @override
  List<ReviewItem> getDueReviews(int textId) {
    const cap = 500;
    final block = calloc<ReviewItemData>(cap);
    final n = _bridge.quizGetReviewItems(textId, block, cap);
    if (n <= 0) {
      calloc.free(block);
      return [];
    }
    final items = [
      for (int i = 0; i < n; i++)
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

  /// 到期错题总数：COUNT 聚合通道，无 500 上限（N15 方案 B）
  /// 失败（未初始化/参数非法）返回 0，与"无到期错题"同语义
  @override
  int getDueReviewCount(int textId) {
    final n = _bridge.quizGetDueReviewCount(textId);
    return n < 0 ? 0 : n;
  }

  /// 错题总数：COUNT 聚合通道，含未到期，无 500 上限
  /// 失败（未初始化/参数非法）返回 0，与"无错题"同语义
  @override
  int getTotalReviewCount(int textId) {
    final n = _bridge.quizGetReviewCount(textId);
    return n < 0 ? 0 : n;
  }

  /// 按 id 取题（复习通道），缺失 id 被跳过
  @override
  List<Question> getQuestionsByIds(List<int> ids) {
    if (ids.isEmpty) return [];
    final idsPtr = calloc<Int32>(ids.length);
    for (int i = 0; i < ids.length; i++) {
      idsPtr[i] = ids[i];
    }
    final block = calloc<QuestionData>(ids.length);
    final n = _bridge.quizGetQuestionsByIds(idsPtr, ids.length, block, ids.length);
    calloc.free(idsPtr);
    if (n <= 0) {
      calloc.free(block);
      return [];
    }
    return [
      for (int i = 0; i < n; i++) Question(block + i, owner: block),
    ];
  }

  /// 文章测验摘要；文章不存在返回 null
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
      return null;
    }
    final summary = QuizAttemptSummary(
        total.value, answered.value, wrong.value);
    calloc.free(total);
    calloc.free(answered);
    calloc.free(wrong);
    return summary;
  }

  /// 答题：C++ 判题并更新能力，返回（更新后用户, 判定结果）
  /// [questionId] 题目 id；[choice] 用户选项（0-3）
  /// [isReview] 错题复习：无答题效应（能力/eta/quiz_count 不变）
  /// 返回 null 表示判题失败（题目不存在/参数越界等）
  @override
  (User?, bool?) applyQuiz(User user, int questionId, int choice,
      {bool isReview = false}) {
    final outUser = User.allocate(calloc);
    final outCorrectPtr = calloc<Int32>();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rc = _bridge.trackerApplyQuiz(
        user.ptr, questionId, choice, now, outUser.ptr, outCorrectPtr,
        isReview ? 1 : 0);
    final correct = rc == BridgeError.ok ? outCorrectPtr.value != 0 : null;
    calloc.free(outCorrectPtr);
    if (rc != BridgeError.ok) {
      outUser.dispose();
      return (null, null);
    }
    return (outUser, correct);
  }
}
