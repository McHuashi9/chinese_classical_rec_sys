import 'package:flutter/foundation.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/engine/recommendation.dart';
import 'package:chinese_classical_rec_sys/engine/profile_repository.dart';
import 'package:chinese_classical_rec_sys/engine/user_init_repository.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/models/user_profile.dart';

class UserController extends ChangeNotifier {
  QuizTracker? _tracker;
  ProfileRepository? _profileRepo;
  UserInitRepository? _initRepo;

  User? _user;
  List<RecommendResult> _recommendations = [];

  List<UserProfile> _profiles = [];
  int? _activeUserId;
  String? _activeProfileName;

  /// 当前强制初始化题组（内存所有权由 UserInitRepository 管理；UI 路由持有期间
  /// 本控制器保留同一引用，路由释放时通过 [disposeQuizQuestions] 统一释放）。
  List<Question>? _initQuestions;

  /// 当前档案是否已完成强制初始化。
  bool _isInitialized = false;

  /// 到期错题数缓存（-1 = 未加载；答题/复习提交后置脏）
  int _reviewCount = -1;

  UserController();

  void initTracker(QuizTracker tracker) { _tracker = tracker; }

  /// 注入档案仓库（生产为 FfiProfileRepository；测试可注入 Fake）
  void initProfiles(ProfileRepository repo) { _profileRepo = repo; }

  /// 注入强制初始化仓库（生产为 FfiUserInitRepository；测试可注入 Fake）
  void initUserInitRepository(UserInitRepository repo) { _initRepo = repo; }

  User? get user => _user;
  double get averageAbility => _user?.averageAbility ?? 0.3;
  List<RecommendResult> get recommendations => _recommendations;

  /// 未删除档案列表（按 id 升序；由 [refreshProfiles] 加载）
  List<UserProfile> get profiles => List.unmodifiable(_profiles);
  int? get activeUserId => _activeUserId;
  String? get activeProfileName => _activeProfileName;

  /// 当前档案是否已完成强制初始化。
  bool get isInitialized => _isInitialized;

  /// 从 FFI 重拉档案列表与当前档案 id；成功返回 true（仓库未注入返回 false）
  bool refreshProfiles() {
    final repo = _profileRepo;
    if (repo == null) return false;
    _profiles = repo.listProfiles();
    final activeId = repo.activeUserId();
    // C++ 未初始化时返回 0 表示"无当前档案"，与 null 同义（避免出现"用户 0"兜底名）
    _activeUserId = activeId > 0 ? activeId : null;
    _activeProfileName = null;
    final active = _activeUserId;
    if (active != null) {
      for (final p in _profiles) {
        if (p.id == active) {
          _activeProfileName = p.name;
          break;
        }
      }
      _activeProfileName ??= '用户 $active';
    }
    notifyListeners();
    return true;
  }

  /// 未删除档案中是否已存在同名（软删档案名可复用）。
  /// [excludeId] 重命名时排除自身。
  bool isProfileNameTaken(String name, {int? excludeId}) {
    final normalized = normalizeProfileName(name);
    if (normalized == null) return false;
    return _profiles.any((p) => p.id != excludeId && p.name == normalized);
  }

  /// 新建档案；成功后刷新列表并返回新 id
  int? createProfile(String name) {
    final repo = _profileRepo;
    final normalized = normalizeProfileName(name);
    if (repo == null || normalized == null) return null;
    final id = repo.createProfile(normalized);
    if (id == null) return null;
    refreshProfiles();
    return id;
  }

  /// 新建档案并继承已有档案能力与历史；成功后刷新列表并返回新 id
  int? createInheritedProfile(String name, int sourceId) {
    final repo = _profileRepo;
    final normalized = normalizeProfileName(name);
    if (repo == null || normalized == null) return null;
    final id = repo.createProfileInherit(normalized, sourceId);
    if (id == null) return null;
    refreshProfiles();
    return id;
  }

  /// 重查当前档案的强制初始化状态（切换档案 / 初始化完成 / 继承后调用）。
  /// 返回是否成功读到状态；未注入仓库返回 false。
  bool refreshInitState() {
    final repo = _initRepo;
    if (repo == null) return false;
    _isInitialized = repo.isInitialized();
    notifyListeners();
    return true;
  }

  /// 取强制初始化题组（6 道）。内部持有当前题组，重复获取会释放旧题组。
  /// 返回的题组由 UI 路由持有，路由销毁时通过 [disposeQuizQuestions] 释放。
  List<Question> getInitQuestions() {
    final repo = _initRepo;
    if (repo == null) return [];
    _disposeInitQuestions();
    _initQuestions = repo.initQuestions();
    return _initQuestions ?? [];
  }

  /// 提交强制初始化题组；成功后更新用户、标记已初始化并通知。
  /// 不自动释放题组：结果页/路由销毁时统一释放。
  bool applyInit(List<int> qids, List<int> choices) {
    final repo = _initRepo;
    if (repo == null || _user == null) return false;
    if (qids.length != choices.length || qids.isEmpty) return false;
    final updated = repo.applyInit(qids, choices);
    if (updated == null) return false;
    _isInitialized = true;
    _updateUser(updated);
    _afterQuizSubmit();
    return true;
  }

  /// 释放当前持有的初始化题组（如初始化流程被放弃）。
  void disposeInitQuestions() {
    _disposeInitQuestions();
  }

  void _disposeInitQuestions() {
    final questions = _initQuestions;
    _initQuestions = null;
    if (questions != null && questions.isNotEmpty) {
      _initRepo?.disposeInitQuestions(questions);
    }
  }

  /// 重命名档案；成功后刷新列表
  bool renameProfile(int id, String name) {
    final repo = _profileRepo;
    final normalized = normalizeProfileName(name);
    if (repo == null || normalized == null) return false;
    if (!repo.renameProfile(id, normalized)) return false;
    refreshProfiles();
    return true;
  }

  /// 软删档案；成功后刷新列表
  bool deleteProfile(int id) {
    final repo = _profileRepo;
    if (repo == null) return false;
    if (!repo.deleteProfile(id)) return false;
    refreshProfiles();
    return true;
  }

  /// 到期错题数（懒查 quiz_get_due_review_count 计数，MyPage 等通过 watch/select 消费）
  /// COUNT 聚合通道无 500 上限（N15 方案 B：总数与列表明细解耦，徽标数字真实）
  /// 懒加载可能发生在 build 期，只缓存不通知；置脏与通知走 _afterQuizSubmit
  int get reviewCount {
    if (_tracker == null) return 0;
    if (_reviewCount < 0) _reviewCount = _tracker!.getDueReviewCount(0);
    return _reviewCount;
  }

  void getRecommendations(RecommendationEngine engine, List<ChineseText> textCache, int topK,
      {Set<int>? excludeTextIds}) {
    if (_user == null) {
      _recommendations = [];
      notifyListeners();
      return;
    }
    final exclude = excludeTextIds ?? const <int>{};
    if (exclude.isEmpty) {
      _recommendations = engine.getRecommendations(_user!, topK, textCache);
    } else {
      // 过取：推荐引擎对全量文章算分后才截断，多要名额成本≈0；
      // 取 topK + 已读篇数，最多被滤掉 fetchK 内全部已读篇目，过滤后仍保证 topK 个
      final fetchK = (topK + exclude.length).clamp(1, textCache.length);
      final all = engine.getRecommendations(_user!, fetchK, textCache);
      _recommendations = filterRecommendations(all, exclude, topK);
    }
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
  QuizBatch getQuizQuestions(int textId) {
    if (_tracker == null) return QuizBatch([]);
    return _tracker!.getQuestionsForText(textId);
  }

  void disposeQuizQuestions(List<Question> questions) {
    if (identical(questions, _initQuestions)) {
      _disposeInitQuestions();
      return;
    }
    _tracker?.disposeQuestions(questions);
  }

  /// 到期错题（textId=0 全部）
  List<ReviewItem> getDueReviews(int textId) {
    if (_tracker == null) return [];
    return _tracker!.getDueReviews(textId);
  }

  /// 按 id 取题（复习通道）
  List<Question> getQuestionsByIds(List<int> ids) {
    if (_tracker == null) return [];
    return _tracker!.getQuestionsByIds(ids);
  }

  /// 文章测验摘要；无 tracker/文章不存在返回 null
  QuizAttemptSummary? getAttemptSummary(int textId) {
    if (_tracker == null) return null;
    return _tracker!.getAttemptSummary(textId);
  }

  /// 提交题组：逐题判分并应用效应（题组后统一判分），更新用户状态
  /// [isReview] 错题复习：判题 + 写复习状态，不产生答题效应。
  /// 返回每题结果（对错 + 答前能力）。
  /// 判题失败时：C++ 侧已逐题落库，失败前已生效的题目不回滚——
  /// 将已生效部分应用到 _user 并返回部分结果；首题即失败返回 null（无任何生效）
  List<QuizAnswer>? submitQuiz(
      List<Question> questions, List<int> choices,
      {bool isReview = false}) {
    if (_user == null || _tracker == null) return null;
    if (questions.length != choices.length) return null;

    final answers = <QuizAnswer>[];
    User current = _user!;
    for (int i = 0; i < questions.length; i++) {
      final before = List<double>.generate(10, (j) => current.getAbility(j));
      final result = _tracker!.applyQuiz(
          current, questions[i].id, choices[i],
          isReview: isReview);
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
        _afterQuizSubmit();
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
    _afterQuizSubmit();
    return answers;
  }

  /// 提交后的收尾：复习状态可能已变（错题入队/移除），置脏错题数并通知
  void _afterQuizSubmit() {
    _reviewCount = -1;
    notifyListeners();
  }

  /// 外部数据变更（远程同步 db_replace 合并用户表）后调用：
  /// 置脏到期错题数缓存并通知，页面懒查刷新
  void invalidateQuizData() {
    _reviewCount = -1;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposeInitQuestions();
    _user?.dispose();
    super.dispose();
  }
}
