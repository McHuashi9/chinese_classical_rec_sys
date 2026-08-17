import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/engine/user_init_repository.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';

class _FakeInitRepo implements UserInitRepository {
  bool initialized = false;
  bool failApply = false;
  int disposeCount = 0;
  List<Question>? questions;
  List<int>? lastQids;
  List<int>? lastChoices;

  @override
  bool isInitialized() => initialized;

  @override
  List<Question> initQuestions() => questions ?? [];

  @override
  void disposeInitQuestions(List<Question> qs) {
    if (qs.isNotEmpty) disposeCount++;
  }

  @override
  User? applyInit(List<int> qids, List<int> choices) {
    lastQids = List.of(qids);
    lastChoices = List.of(choices);
    if (failApply) return null;
    final u = User.allocate(calloc);
    return u;
  }
}

class _NoopTracker implements QuizTracker {
  @override
  User? applyRead(User user, int textId, double readTime) => null;

  @override
  (User?, bool?) applyQuiz(User user, int questionId, int choice,
      {bool isReview = false}) =>
      (null, null);

  @override
  void disposeQuestions(List<Question> questions) {}

  @override
  QuizBatch getQuestionsForText(int textId) => QuizBatch([]);

  @override
  List<ReviewItem> getDueReviews(int textId) => [];

  @override
  int getDueReviewCount(int textId) => 0;

  @override
  List<Question> getQuestionsByIds(List<int> ids) => [];

  @override
  QuizAttemptSummary? getAttemptSummary(int textId) => null;

  @override
  User? prune(User user) => null;
}

void main() {
  group('UserController 强制初始化状态', () {
    late UserController ctrl;
    late _FakeInitRepo repo;

    setUp(() {
      ctrl = UserController();
      repo = _FakeInitRepo();
      ctrl.initTracker(_NoopTracker());
      ctrl.initUserInitRepository(repo);
      ctrl.setUser(User.allocate(calloc));
    });

    tearDown(() => ctrl.dispose());

    test('refreshInitState 从仓库读取并通知', () {
      repo.initialized = false;
      var notified = 0;
      ctrl.addListener(() => notified++);
      expect(ctrl.refreshInitState(), isTrue);
      expect(ctrl.isInitialized, isFalse);
      expect(notified, 1);

      repo.initialized = true;
      expect(ctrl.refreshInitState(), isTrue);
      expect(ctrl.isInitialized, isTrue);
      expect(notified, 2);
    });

    test('未注入仓库时 refreshInitState 返回 false', () {
      final bare = UserController();
      expect(bare.refreshInitState(), isFalse);
      bare.dispose();
    });

    test('getInitQuestions 缓存题组并释放旧题组', () {
      final block1 = calloc<QuestionData>(2);
      final q1 = [
        Question(block1, owner: block1),
        Question(block1 + 1, owner: block1),
      ];
      final block2 = calloc<QuestionData>(1);
      final q2 = [Question(block2, owner: block2)];
      repo.questions = q1;
      expect(ctrl.getInitQuestions(), same(q1));
      repo.questions = q2;
      expect(ctrl.getInitQuestions(), same(q2));
      expect(repo.disposeCount, 1);
      calloc.free(block2);
    });

    test('applyInit 成功：标记已初始化、更新用户并通知', () {
      repo.initialized = false;
      var notified = 0;
      ctrl.addListener(() => notified++);
      final before = ctrl.user;
      final ok = ctrl.applyInit([1, 2, 3], [0, 1, 0]);
      expect(ok, isTrue);
      expect(ctrl.isInitialized, isTrue);
      expect(repo.lastQids, [1, 2, 3]);
      expect(repo.lastChoices, [0, 1, 0]);
      expect(identical(ctrl.user, before), isFalse);
      expect(notified, greaterThanOrEqualTo(1));
    });

    test('applyInit 失败：不改变初始化状态', () {
      repo.failApply = true;
      final before = ctrl.user;
      final ok = ctrl.applyInit([1], [0]);
      expect(ok, isFalse);
      expect(ctrl.isInitialized, isFalse);
      expect(identical(ctrl.user, before), isTrue);
    });

    test('disposeInitQuestions 释放当前题组', () {
      final block = calloc<QuestionData>(1);
      repo.questions = [Question(block, owner: block)];
      ctrl.getInitQuestions();
      ctrl.disposeInitQuestions();
      expect(repo.disposeCount, 1);
      calloc.free(block);
    });
  });
}
