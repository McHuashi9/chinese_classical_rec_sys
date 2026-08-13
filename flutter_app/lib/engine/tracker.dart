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

/// 知识追踪能力抽象：UserController 依赖此接口（生产注入 KnowledgeTracker，
/// 测试注入 Fake）——FFI 依赖链（NativeBridge→DynamicLibrary）无法在单测中构造。
abstract class QuizTracker {
  /// 记录阅读事件，返回更新后的用户或 null（阅读时间不足）
  User? applyRead(User user, int textId, double readTime);

  /// 清理过期增量，返回更新后的用户
  User? prune(User user);

  /// 取该篇文章的题组（整块内存，用后由调用方 disposeQuestions 释放）
  List<Question> getQuestionsForText(int textId);

  /// 释放 [getQuestionsForText] 返回的题组内存（恰好一次）
  void disposeQuestions(List<Question> questions);

  /// 答题：判题并更新能力，返回（更新后用户, 判定结果）。
  /// 内存契约：失败必须成对返回 (null, null)；成功必须返回新分配的 User
  /// （所有权转移给调用方，由调用方 dispose）。
  (User?, bool?) applyQuiz(User user, int questionId, int choice);
}

/// 知识追踪 FFI 封装
class KnowledgeTracker implements QuizTracker {
  final NativeBridge _bridge;
  static const int quizBatchSize = 5;

  KnowledgeTracker(this._bridge);

  /// 记录阅读事件，更新用户能力
  /// [readTime] 阅读时长(秒)，>=30s 才会触发更新
  /// 返回更新后的用户或 null (读取时间不足)
  @override
  User? applyRead(User user, int textId, double readTime) {
    if (readTime < 30) return null;

    final outUser = User.allocate(calloc);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rc = _bridge.trackerApplyRead(
        user.ptr, textId, readTime, now, outUser.ptr);
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

  /// 取该篇文章的题目（最多 [quizBatchSize] 题；题量不足返回实际数量）
  /// 返回的题组为整块分配内存，用完调用 [disposeQuestions] 统一释放。
  /// 注意：count<0（如 BRIDGE_ERR_TEXT 文章不存在）与 0（无题）统一按空返回——
  /// 当前调用方传的 textId 必然来自已读文章，无需区分；若未来按 id 直接取题需拆开处理
  @override
  List<Question> getQuestionsForText(int textId) {
    const max = quizBatchSize;
    final block = calloc<QuestionData>(max);
    final count = _bridge.questionGetByText(textId, block, max);
    if (count <= 0) {
      calloc.free(block);
      return [];
    }
    return [
      for (int i = 0; i < count; i++)
        Question(block + i, owner: block),
    ];
  }

  /// 释放 [getQuestionsForText] 返回的题组内存
  /// 注意：必须恰好调用一次（所有权单一归属），重复释放同一题组会导致 double free
  @override
  void disposeQuestions(List<Question> questions) {
    if (questions.isEmpty) return;
    calloc.free(questions.first.owner);
  }

  /// 答题：C++ 判题并更新能力，返回（更新后用户, 判定结果）
  /// [questionId] 题目 id；[choice] 用户选项（0-3）
  /// 返回 null 表示判题失败（题目不存在/参数越界等）
  @override
  (User?, bool?) applyQuiz(User user, int questionId, int choice) {
    final outUser = User.allocate(calloc);
    final outCorrectPtr = calloc<Int32>();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rc = _bridge.trackerApplyQuiz(
        user.ptr, questionId, choice, now, outUser.ptr, outCorrectPtr);
    final correct = rc == BridgeError.ok ? outCorrectPtr.value != 0 : null;
    calloc.free(outCorrectPtr);
    if (rc != BridgeError.ok) {
      outUser.dispose();
      return (null, null);
    }
    return (outUser, correct);
  }
}
