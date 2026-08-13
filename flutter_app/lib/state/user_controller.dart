import 'package:flutter/foundation.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/engine/recommendation.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';

class UserController extends ChangeNotifier {
  QuizTracker? _tracker;

  User? _user;
  List<RecommendResult> _recommendations = [];

  UserController();

  void initTracker(QuizTracker tracker) { _tracker = tracker; }

  User? get user => _user;
  double get averageAbility => _user?.averageAbility ?? 0.3;
  List<RecommendResult> get recommendations => _recommendations;

  void getRecommendations(RecommendationEngine engine, List<ChineseText> textCache, int topK) {
    if (_user == null) {
      _recommendations = [];
      notifyListeners();
      return;
    }
    _recommendations = engine.getRecommendations(_user!, topK, textCache);
    notifyListeners();
  }

  bool applyReadEffect(int textId, double seconds) {
    if (_user == null || _tracker == null) return false;
    final updated = _tracker!.applyRead(_user!, textId, seconds);
    return _updateUser(updated);
  }

  bool _updateUser(User? updated) {
    if (updated == null) return false;
    // 无变化（如空题组）：直接采纳，避免 dispose 后对悬垂指针 prune
    if (identical(updated, _user)) return true;
    _user!.dispose();
    final pruned = _tracker!.prune(updated);
    if (pruned != null) {
      _user = pruned;
      updated.dispose();
    } else {
      _user = updated;
    }
    return true;
  }

  void setUser(User? user) {
    final old = _user;
    _user = user;
    old?.dispose();
  }

  /// 取该篇文章的题组（整块内存，用后由调用方释放）
  List<Question> getQuizQuestions(int textId) {
    if (_tracker == null) return [];
    return _tracker!.getQuestionsForText(textId);
  }

  void disposeQuizQuestions(List<Question> questions) {
    _tracker?.disposeQuestions(questions);
  }

  /// 提交题组：逐题判分并应用效应（题组后统一判分），更新用户状态
  /// 返回每题结果（对错 + 答前能力）。
  /// 判题失败时：C++ 侧已逐题落库，失败前已生效的题目不回滚——
  /// 将已生效部分应用到 _user 并返回部分结果；首题即失败返回 null（无任何生效）
  List<QuizAnswer>? submitQuiz(
      List<Question> questions, List<int> choices) {
    if (_user == null || _tracker == null) return null;
    if (questions.length != choices.length) return null;

    final answers = <QuizAnswer>[];
    User current = _user!;
    for (int i = 0; i < questions.length; i++) {
      final before = List<double>.generate(10, (j) => current.getAbility(j));
      final result = _tracker!.applyQuiz(current, questions[i].id, choices[i]);
      final updated = result.$1;
      final correct = result.$2;
      if (updated == null || correct == null) {
        // 契约外异常（updated 非 null 但 correct 为 null）：释放避免泄漏
        updated?.dispose();
        // 首题失败：无生效，保留 _user
        if (answers.isEmpty) return null;
        // 部分成功：C++ 已落库前几题，同步内存态避免下次重复生效（与成功路径一致带 prune）
        if (i > 0) {
          _updateUser(current);
        }
        notifyListeners();
        return answers;
      }
      answers.add(QuizAnswer(
        questionId: questions[i].id,
        selected: choices[i],
        correct: correct,
        abilityBefore: before,
      ));
      if (i > 0) current.dispose();
      current = updated;
    }
    // 成功路径与阅读链路一致：prune 过期增量（quiz 增量同样会被裁剪合并）
    _updateUser(current);
    notifyListeners();
    return answers;
  }

  @override
  void dispose() {
    _user?.dispose();
    super.dispose();
  }
}
