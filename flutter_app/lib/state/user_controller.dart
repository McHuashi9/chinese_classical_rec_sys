import 'package:flutter/foundation.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/engine/recommendation.dart';
import 'package:chinese_classical_rec_sys/engine/profile_repository.dart';
import 'package:chinese_classical_rec_sys/engine/user_init_repository.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/models/user_profile.dart';

import 'package:chinese_classical_rec_sys/engine/ffi_call.dart';
import 'package:chinese_classical_rec_sys/engine/app_logger.dart';

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

  /// 错题总数缓存（-1 = 未加载；答题/复习提交后置脏）
  int _totalReviewCount = -1;

  /// 最近一次错题计数查询的 FFI 失败；null = 上次查询成功。
  /// getter 为兼容 build 期调用不抛出，但调用方/诊断可据此区分“0 条”与“查询失败”。
  FfiException? _quizDataError;

  UserController();

  void initTracker(QuizTracker tracker) {
    _tracker = tracker;
  }

  /// 注入档案仓库（生产为 FfiProfileRepository；测试可注入 Fake）
  void initProfiles(ProfileRepository repo) {
    _profileRepo = repo;
  }

  /// 注入强制初始化仓库（生产为 FfiUserInitRepository；测试可注入 Fake）
  void initUserInitRepository(UserInitRepository repo) {
    _initRepo = repo;
  }

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
    _profiles.sort((a, b) {
      final byLastUsed = b.lastUsedAt.compareTo(a.lastUsedAt);
      if (byLastUsed != 0) return byLastUsed;
      return a.id.compareTo(b.id);
    });
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
    if (repo == null) {
      AppLogger().warn('createProfile 失败: 档案仓库未注入');
      return null;
    }
    final normalized = normalizeProfileName(name);
    if (normalized == null) {
      AppLogger().warn('createProfile 失败: 档案名无效');
      return null;
    }
    final id = repo.createProfile(normalized);
    if (id == null) {
      AppLogger().error('createProfile 失败: 仓库返回空 id');
      return null;
    }
    refreshProfiles();
    AppLogger().info('createProfile 成功 id=$id');
    return id;
  }

  /// 新建档案并继承已有档案能力与历史；成功后刷新列表并返回新 id
  int? createInheritedProfile(String name, int sourceId) {
    final repo = _profileRepo;
    if (repo == null) {
      AppLogger().warn('createInheritedProfile 失败: 档案仓库未注入');
      return null;
    }
    final normalized = normalizeProfileName(name);
    if (normalized == null) {
      AppLogger().warn('createInheritedProfile 失败: 档案名无效 source_id=$sourceId');
      return null;
    }
    final id = repo.createProfileInherit(normalized, sourceId);
    if (id == null) {
      AppLogger()
          .error('createInheritedProfile 失败: 仓库返回空 id source_id=$sourceId');
      return null;
    }
    refreshProfiles();
    AppLogger().info('createInheritedProfile 成功 id=$id source_id=$sourceId');
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
    if (repo == null || _user == null) {
      AppLogger().warn('applyInit 失败: 初始化仓库或用户未就绪');
      return false;
    }
    if (qids.length != choices.length || qids.isEmpty) {
      AppLogger().warn(
          'applyInit 失败: 答案数量不合法 questions=${qids.length} choices=${choices.length}');
      return false;
    }
    final updated = repo.applyInit(qids, choices);
    if (updated == null) {
      AppLogger().error('applyInit 失败: 仓库返回空结果 count=${qids.length}');
      return false;
    }
    _isInitialized = true;
    _updateUser(updated);
    _afterQuizSubmit();
    AppLogger().info('applyInit 成功 count=${qids.length}');
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
    if (repo == null) {
      AppLogger().warn('renameProfile 失败: 档案仓库未注入 id=$id');
      return false;
    }
    final normalized = normalizeProfileName(name);
    if (normalized == null) {
      AppLogger().warn('renameProfile 失败: 档案名无效 id=$id');
      return false;
    }
    if (!repo.renameProfile(id, normalized)) {
      AppLogger().error('renameProfile 失败: 仓库拒绝 id=$id');
      return false;
    }
    refreshProfiles();
    AppLogger().info('renameProfile 成功 id=$id');
    return true;
  }

  /// 软删档案；成功后刷新列表
  bool deleteProfile(int id) {
    final repo = _profileRepo;
    if (repo == null) {
      AppLogger().warn('deleteProfile 失败: 档案仓库未注入 id=$id');
      return false;
    }
    if (!repo.deleteProfile(id)) {
      AppLogger().error('deleteProfile 失败: 仓库拒绝 id=$id');
      return false;
    }
    refreshProfiles();
    AppLogger().info('deleteProfile 成功 id=$id');
    return true;
  }

  /// 最近一次错题计数查询的 FFI 失败；null = 上次查询成功。
  FfiException? get quizDataError => _quizDataError;

  /// 到期错题数（懒查 quiz_get_due_review_count 计数，MyPage 等通过 watch/select 消费）
  /// COUNT 聚合通道无 500 上限（N15 方案 B：总数与列表明细解耦，徽标数字真实）
  /// 懒加载可能发生在 build 期，只缓存不通知；置脏与通知走 _afterQuizSubmit。
  /// 这是有意设计：避免每次 build 都触发 FFI，同时保证提交/数据变更后能刷新。
  /// FFI 失败记录到 [quizDataError] 并返回 0 供旧 UI 继续渲染；0 本身不冒充成功。
  int get reviewCount {
    if (_tracker == null) return 0;
    if (_reviewCount < 0) {
      try {
        _reviewCount = _tracker!.getDueReviewCount(0);
        _quizDataError = null;
      } on FfiException catch (e) {
        _quizDataError = e;
        return 0;
      }
    }
    return _reviewCount;
  }

  /// 错题总数（懒查 quiz_get_review_count 计数，MyPage 等通过 watch/select 消费）
  /// 含未到期条目，COUNT 聚合通道无 500 上限；置脏与通知走 _afterQuizSubmit。
  /// 这也是有意设计：getter 内只做一次性懒查并缓存，不在 build 期反复调用 FFI；
  /// 提交/复习/数据变更后由 [_afterQuizSubmit] 或 [invalidateQuizData] 置脏并通知。
  int get totalReviewCount {
    if (_tracker == null) return 0;
    if (_totalReviewCount < 0) {
      try {
        _totalReviewCount = _tracker!.getTotalReviewCount(0);
        _quizDataError = null;
      } on FfiException catch (e) {
        _quizDataError = e;
        return 0;
      }
    }
    return _totalReviewCount;
  }

  void getRecommendations(
      RecommendationEngine engine, List<ChineseText> textCache, int topK,
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

  /// 应用阅读效应；FFI 失败抛 [FfiException]（由调用方决定如何提示）。
  bool applyReadEffect(int textId, double seconds) {
    if (_user == null || _tracker == null) return false;
    final updated = _tracker!.applyRead(_user!, textId, seconds);
    return _updateUser(updated);
  }

  /// 采纳新的用户状态并统一通知。
  ///
  /// prune 是增量清理的附带步骤：若它失败，主效应已经由 C++ 事务提交，
  /// 此处记录失败并继续采纳 updated，避免把“主操作成功”误报为失败；
  /// 其他 FFI 失败仍向上抛，由调用方展示。
  bool _updateUser(User updated) {
    // 无变化（如空题组）：直接采纳，避免 dispose 后对悬垂指针 prune
    if (identical(updated, _user)) return true;
    User effective = updated;
    try {
      final pruned = _tracker!.prune(updated);
      effective = pruned;
      if (!identical(pruned, updated)) updated.dispose();
    } on FfiException catch (e) {
      AppLogger().warn('用户状态已更新，但 prune 失败，保留未裁剪状态: $e');
    }
    _user!.dispose();
    _user = effective;
    // 用户状态变化统一通知：阅读/初始化/答题都经此路径，
    // UI 通过 context.watch/select 能可靠刷新，不依赖祖先巧合重建。
    notifyListeners();
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

  /// 提交题组：单次 FFI 批量判分并应用效应，更新用户状态。
  /// [isReview] 错题复习：判题 + 写复习状态，不产生答题效应。
  /// 返回每题结果（对错 + 答前能力）。
  ///
  /// 失败契约：状态前置条件不满足返回 null；C++ FFI 失败抛 [FfiException]，
  /// 且 C++ 事务保证整批回滚——不存在“前几题已生效”的部分成功返回值。
  List<QuizAnswer>? submitQuiz(List<Question> questions, List<int> choices,
      {bool isReview = false}) {
    if (_user == null || _tracker == null) {
      AppLogger().warn('submitQuiz 失败: 用户或 tracker 未就绪 is_review=$isReview');
      return null;
    }
    if (questions.length != choices.length) {
      AppLogger().warn(
          'submitQuiz 失败: 题目/答案数量不匹配 questions=${questions.length} choices=${choices.length}');
      return null;
    }
    if (questions.isEmpty) {
      AppLogger().debug('submitQuiz 跳过: 空题组');
      return const [];
    }

    try {
      final result = _tracker!.applyQuizBatch(
        _user!,
        [for (final q in questions) q.id],
        choices,
        isReview: isReview,
      );
      _updateUser(result.user);
      _afterQuizSubmit();
      AppLogger()
          .info('submitQuiz 完成 count=${questions.length} is_review=$isReview');
      return [
        for (int i = 0; i < questions.length; i++)
          QuizAnswer(
            questionId: questions[i].id,
            selected: choices[i],
            correct: result.correct[i],
            abilityBefore: result.abilityBefore[i],
          ),
      ];
    } catch (e) {
      AppLogger().error(
          'submitQuiz 失败 count=${questions.length} is_review=$isReview: $e');
      rethrow;
    }
  }

  /// 提交后的收尾：复习状态可能已变（错题入队/移除），置脏错题数。
  /// 不在这里通知：调用方在用户更新后已经过 [_updateUser] 统一通知，避免重复 rebuild。
  void _afterQuizSubmit() {
    _reviewCount = -1;
    _totalReviewCount = -1;
  }

  /// 外部数据变更（远程同步 db_replace 合并用户表）后调用：
  /// 置脏到期错题数缓存并通知，页面懒查刷新
  void invalidateQuizData() {
    _reviewCount = -1;
    _totalReviewCount = -1;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposeInitQuestions();
    _user?.dispose();
    super.dispose();
  }
}
