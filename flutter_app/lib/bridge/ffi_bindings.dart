import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'c_types.dart';

/// Dart FFI 函数表 — 绑定 libchinese_core.so 的所有 C 函数
final class NativeBridge {
  static NativeBridge? instance;

  final DynamicLibrary _lib;

  // ─── 生命周期 ────────────────────────────────────────────────
  late final int Function(Pointer<Utf8> dbPath) dbOpen;
  late final void Function() dbClose;
  late final int Function(Pointer<Utf8> newPath, Pointer<Utf8> curPath) dbReplace;

  // ─── 用户 ────────────────────────────────────────────────────
  late final int Function(Pointer<UserData> out) userLoad;
  late final int Function(Pointer<UserData> inp) userSave;
  late final int Function() userInitDefault;

  // ─── 文本 ────────────────────────────────────────────────────
  late final int Function() textGetCount;
  late final void Function(Pointer<TextInfo> out, int maxCount) textGetAll;
  late final int Function(int id, Pointer<TextDetail> out) textGetDetail;
  late final int Function(int id, Pointer<Utf8> out, int maxLen) textGetAnnotations;
  late final int Function(int id, Pointer<Utf8> out, int maxLen) textGetTranslation;

  // ─── 推荐 ────────────────────────────────────────────────────
  late final int Function(
    Pointer<UserData> user,
    int topK,
    Pointer<Int32> outIds,
    Pointer<Double> outProbs,
    int outIdsCapacity,
    int outProbsCapacity,
  ) recommend;

  // ─── 知识追踪 ────────────────────────────────────────────────
  late final int Function(
    Pointer<UserData> user,
    int textId,
    double readTime,
    int timestamp,
    Pointer<UserData> outUser,
  ) trackerApplyRead;

  late final int Function(
    Pointer<UserData> user,
    int now,
    Pointer<UserData> outUser,
  ) trackerApplyForgetting;

  late final int Function(
    Pointer<UserData> user,
    int now,
    Pointer<UserData> outUser,
  ) trackerPrune;

  /// 答题效应（本篇文章测验）: C++ 按 question_id 查题判题并更新能力
  /// 返回判题结果（correct: 1 对 / 0 错）到 outCorrect；
  /// isReview=1（错题复习）跳过能力效应，只判题 + 写复习状态
  late final int Function(
    Pointer<UserData> user,
    int questionId,
    int userChoice,
    int timestamp,
    Pointer<UserData> outUser,
    Pointer<Int32> outCorrect,
    int isReview,
  ) trackerApplyQuiz;

  /// 取题: 按文章取题（上限 maxCount，若题量不足返回实际数量；不含 answer_index）
  /// answeredAll 输出：1 = 该篇已无未答题（含复习记录排除）
  late final int Function(
    int textId,
    Pointer<QuestionData> out,
    int maxCount,
    Pointer<Int32> answeredAll,
  ) questionGetByText;

  /// 到期错题列表（textId=0 全部；上限 maxCount）
  late final int Function(int textId, Pointer<ReviewItemData> out, int maxCount)
      quizGetReviewItems;

  /// 按 id 取题（复习通道，不受"排除已答"影响；缺失 id 跳过）
  late final int Function(
    Pointer<Int32> ids,
    int count,
    Pointer<QuestionData> out,
    int maxCount,
  ) quizGetQuestionsByIds;

  /// 文章测验摘要：total=总题数 answered=已答数 wrong=错题数（review_items 现役）
  late final int Function(
    int textId,
    Pointer<Int32> total,
    Pointer<Int32> answered,
    Pointer<Int32> wrong,
  ) quizGetAttemptSummary;

  // ─── 阅读历史 ────────────────────────────────────────────────
  late final int Function(int textId, double readTime, int timestamp)
      historyAddRecord;

  late final int Function(int limit, Pointer<ReadingRecordData> out, int maxCount)
      historyGetRecent;

  late final int Function() historyGetTotalCount;

  late final int Function(Pointer<Int32> out, int maxCount)
      historyGetTrackedTextIds;

  // ─── 日志 ────────────────────────────────────────────────────
  late final void Function(int level, Pointer<Utf8> message) logWrite;
  late final void Function(Pointer<Utf8> level) logSetLevel;

  // ──────────────────────────────────────────────────────────────

  NativeBridge.fromLib(DynamicLibrary lib) : _lib = lib {
    dbOpen = _lib.lookupFunction<
        Int32 Function(Pointer<Utf8>),
        int Function(Pointer<Utf8>)>('db_open');

    dbClose = _lib.lookupFunction<
        Void Function(),
        void Function()>('db_close');

    dbReplace = _lib.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Utf8>, Pointer<Utf8>)>('db_replace');

    userLoad = _lib.lookupFunction<
        Int32 Function(Pointer<UserData>),
        int Function(Pointer<UserData>)>('user_load');

    userSave = _lib.lookupFunction<
        Int32 Function(Pointer<UserData>),
        int Function(Pointer<UserData>)>('user_save');

    userInitDefault = _lib.lookupFunction<
        Int32 Function(),
        int Function()>('user_init_default');

    textGetCount = _lib.lookupFunction<
        Int32 Function(),
        int Function()>('text_get_count');

    textGetAll = _lib.lookupFunction<
        Void Function(Pointer<TextInfo>, Int32),
        void Function(Pointer<TextInfo>, int)>('text_get_all');

    textGetDetail = _lib.lookupFunction<
        Int32 Function(Int32, Pointer<TextDetail>),
        int Function(int, Pointer<TextDetail>)>('text_get_detail');

    textGetAnnotations = _lib.lookupFunction<
        Int32 Function(Int32, Pointer<Utf8>, Int32),
        int Function(int, Pointer<Utf8>, int)>('text_get_annotations');

    textGetTranslation = _lib.lookupFunction<
        Int32 Function(Int32, Pointer<Utf8>, Int32),
        int Function(int, Pointer<Utf8>, int)>('text_get_translation');

    recommend = _lib.lookupFunction<
        Int32 Function(Pointer<UserData>, Int32, Pointer<Int32>, Pointer<Double>, Int32, Int32),
        int Function(Pointer<UserData>, int, Pointer<Int32>, Pointer<Double>, int, int)>(
            'recommend');

    trackerApplyRead = _lib.lookupFunction<
        Int32 Function(Pointer<UserData>, Int32, Double, Int64, Pointer<UserData>),
        int Function(Pointer<UserData>, int, double, int, Pointer<UserData>)>(
            'tracker_apply_read');

    trackerApplyForgetting = _lib.lookupFunction<
        Int32 Function(Pointer<UserData>, Int64, Pointer<UserData>),
        int Function(Pointer<UserData>, int, Pointer<UserData>)>(
            'tracker_apply_forgetting');

    trackerPrune = _lib.lookupFunction<
        Int32 Function(Pointer<UserData>, Int64, Pointer<UserData>),
        int Function(Pointer<UserData>, int, Pointer<UserData>)>(
            'tracker_prune');

    trackerApplyQuiz = _lib.lookupFunction<
        Int32 Function(Pointer<UserData>, Int32, Int32, Int64, Pointer<UserData>, Pointer<Int32>, Int32),
        int Function(Pointer<UserData>, int, int, int, Pointer<UserData>, Pointer<Int32>, int)>(
            'tracker_apply_quiz');

    questionGetByText = _lib.lookupFunction<
        Int32 Function(Int32, Pointer<QuestionData>, Int32, Pointer<Int32>),
        int Function(int, Pointer<QuestionData>, int, Pointer<Int32>)>(
            'question_get_by_text');

    quizGetReviewItems = _lib.lookupFunction<
        Int32 Function(Int32, Pointer<ReviewItemData>, Int32),
        int Function(int, Pointer<ReviewItemData>, int)>('quiz_get_review_items');

    quizGetQuestionsByIds = _lib.lookupFunction<
        Int32 Function(Pointer<Int32>, Int32, Pointer<QuestionData>, Int32),
        int Function(Pointer<Int32>, int, Pointer<QuestionData>, int)>(
            'quiz_get_questions_by_ids');

    quizGetAttemptSummary = _lib.lookupFunction<
        Int32 Function(Int32, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>),
        int Function(int, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>)>(
            'quiz_get_attempt_summary');

    historyAddRecord = _lib.lookupFunction<
        Int32 Function(Int32, Double, Int64),
        int Function(int, double, int)>('history_add_record');

    historyGetRecent = _lib.lookupFunction<
        Int32 Function(Int32, Pointer<ReadingRecordData>, Int32),
        int Function(int, Pointer<ReadingRecordData>, int)>('history_get_recent');

    historyGetTotalCount = _lib.lookupFunction<
        Int32 Function(),
        int Function()>('history_get_total_count');

    historyGetTrackedTextIds = _lib.lookupFunction<
        Int32 Function(Pointer<Int32>, Int32),
        int Function(Pointer<Int32>, int)>('history_get_tracked_text_ids');

    logWrite = _lib.lookupFunction<
        Void Function(Int32, Pointer<Utf8>),
        void Function(int, Pointer<Utf8>)>('log_write');

    logSetLevel = _lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)>('log_set_level');

    instance = this;
  }
}
