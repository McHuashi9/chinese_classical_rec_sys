// 桥层用户域（v1.4.0 工作项 3）：user_load / user_save / user_init_default /
// user_is_initialized / user_init_questions / user_init_apply / user_list / user_active_id /
// user_create / user_create_inherit / user_switch / user_rename / user_delete，共 13 个导出符号。
//
// 工作项 2 下沉：初始化取题（单条 IN 查询）→ QuizRepository；作答流水 → QuizRepository；
// 清增量 → LearningIncrementRepository；q_key 清单 → initQKeys() 单源；事务 → SqlTransaction。

#include "bridge_internal.h"

#include "core/MathUtils.h"
#include "utils/FeatureExtractor.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace {

bool isInitQKey(const std::string& key)
{
    const auto& keys = initQKeys();
    return std::find(keys.begin(), keys.end(), key) != keys.end();
}

// Beta(3,7) 先验密度（未归一化）：u^(α-1) (1-u)^(β-1)
double initPriorDensity(double u)
{
    return std::pow(u, 2.0) * std::pow(1.0 - u, 6.0);
}

// 对单个维度的一组 (题目难度 d_j, 是否答对) 观测求后验均值
double initPosteriorMean(const std::vector<std::pair<double, int>>& observations)
{
    constexpr double kStep = 0.001;
    double sum = 0.0;
    double norm = 0.0;
    for (double u = 0.0; u <= 1.0 + 1e-12; u += kStep) {
        double w = initPriorDensity(u);
        for (const auto& [d, correct] : observations) {
            const double p = math_utils::expectedAccuracy(u, d);
            w *= correct ? p : (1.0 - p);
        }
        sum += u * w;
        norm += w;
    }
    return norm > 0.0 ? sum / norm : 0.3;
}

}  // namespace

extern "C" CHINESE_CORE_EXPORT int user_load(UserData* out)
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    if (!out) return BRIDGE_ERR_GENERIC;
    user_to_c(*S().user, out);
    return BRIDGE_OK;
    });
}

extern "C" CHINESE_CORE_EXPORT int user_save(const UserData* in)
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    if (!in) return BRIDGE_ERR_GENERIC;
    c_to_user(in, *S().user);
    if (S().userRepo->saveUser(*S().user, S().activeUserId)) {
        return BRIDGE_OK;
    }
    LOG_ERROR("bridge: user_save 失败");
    return BRIDGE_ERR_GENERIC;
    });
}

extern "C" CHINESE_CORE_EXPORT int user_init_default()
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    S().user->initializeDefault();
    if (S().userRepo->saveUser(*S().user, S().activeUserId)) {
        return BRIDGE_OK;
    }
    return BRIDGE_ERR_GENERIC;
    });
}

// ─── 强制用户初始化 ──────────────────────────────────────────────────────────────

extern "C" CHINESE_CORE_EXPORT int user_is_initialized()
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    return S().userRepo->isInitialized(S().activeUserId) ? 1 : 0;
    });
}

extern "C" CHINESE_CORE_EXPORT int user_init_questions(QuestionData* out, int max_count)
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    if (!out || max_count <= 0) return BRIDGE_ERR_GENERIC;

    // 单条 IN 查询（原按 6 个 q_key 逐个 prepare），结果按 initQKeys() 顺序回填
    const QuizQuestions result = S().quizRepo->getInitQuestions(max_count);
    if (result.status != QuizStatus::Ok) {
        if (!result.missingKey.empty()) {
            LOG_ERROR("bridge: user_init_questions 缺少初始化题 q_key={}", result.missingKey);
        } else {
            LOG_ERROR("bridge: user_init_questions 查询失败: {}", S().db->getLastError());
        }
        return BRIDGE_ERR_DB_CONTENT;
    }
    for (size_t i = 0; i < result.rows.size(); i++) {
        fillQuestionRow(result.rows[i], out[i]);
    }
    return static_cast<int>(result.rows.size());
    });
}

// 一次性完成 6 道初始化题：判题、写 quiz_attempts(is_init=1)、贝叶斯后验、
// 清空被覆盖维度增量、置 initialized=1。不写 review_items、不重复写阅读历史。
extern "C" CHINESE_CORE_EXPORT int user_init_apply(const int* qids, const int* choices,
                                                   int count, int64_t timestamp,
                                                   UserData* out_user)
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    if (S().userRepo->isInitialized(S().activeUserId)) {
        LOG_WARN("bridge: user_init_apply 拒绝：当前档案已完成初始化，无补测");
        return BRIDGE_ERR_GENERIC;
    }
    if (!qids || !choices || !out_user) return BRIDGE_ERR_GENERIC;
    if (count != static_cast<int>(initQKeys().size())) {
        LOG_WARN("bridge: user_init_apply 必须一次性提交 {} 题，收到 {}", initQKeys().size(), count);
        return BRIDGE_ERR_GENERIC;
    }

    struct InitItem {
        int qid;
        int textId;
        int answer;
        int correct;
        std::vector<int> dims;
    };
    std::vector<InitItem> items;
    items.reserve(count);
    std::map<int, std::vector<std::pair<double, int>>> dimObs;
    std::set<int> coveredDims;
    std::set<int> seenQids;

    for (int i = 0; i < count; i++) {
        const int qid = qids[i];
        const int choice = choices[i];
        if (choice < 0 || choice > 3) {
            LOG_WARN("bridge: user_init_apply choice 越界 qid={} choice={}", qid, choice);
            return BRIDGE_ERR_GENERIC;
        }
        if (!seenQids.insert(qid).second) {
            LOG_WARN("bridge: user_init_apply 重复题 qid={}", qid);
            return BRIDGE_ERR_GENERIC;
        }

        const QuizQuestionInfo info = S().quizRepo->getQuestionInfo(qid);
        if (info.status != QuizStatus::Ok) {
            LOG_ERROR("bridge: user_init_apply 题目查询失败 qid={}: {}", qid, S().db->getLastError());
            return BRIDGE_ERR_GENERIC;
        }
        if (!info.found) {
            LOG_WARN("bridge: user_init_apply 题目不存在 qid={}", qid);
            return BRIDGE_ERR_TEXT;
        }

        const std::string qkeyStr = info.qKey;
        const int textId = info.textId;
        const int answer = info.answerIndex;
        const std::string dimsStr = info.dims;

        if (!isInitQKey(qkeyStr)) {
            LOG_WARN("bridge: user_init_apply 非初始化题 qid={} q_key={}", qid, qkeyStr);
            return BRIDGE_ERR_GENERIC;
        }
        auto it = S().textIndex->find(textId);
        if (it == S().textIndex->end()) {
            LOG_WARN("bridge: user_init_apply 文章不存在 text_id={}", textId);
            return BRIDGE_ERR_TEXT;
        }
        if (answer < 0 || answer > 3) {
            LOG_WARN("bridge: user_init_apply answer_index 越界 qid={}", qid);
            return BRIDGE_ERR_GENERIC;
        }

        InitItem item;
        item.qid = qid;
        item.textId = textId;
        item.answer = answer;
        item.correct = (choice == answer) ? 1 : 0;
        std::stringstream ss(dimsStr);
        std::string tok;
        while (std::getline(ss, tok, ',')) {
            if (!tok.empty()) item.dims.push_back(std::atoi(tok.c_str()));
        }
        if (item.dims.empty()) {
            LOG_WARN("bridge: user_init_apply dims 为空 qid={}", qid);
            return BRIDGE_ERR_GENERIC;
        }
        for (int d : item.dims) {
            if (d < 0 || d >= 10) {
                LOG_WARN("bridge: user_init_apply 维度越界 qid={} d={}", qid, d);
                return BRIDGE_ERR_GENERIC;
            }
            const double dj = FeatureExtractor::getNormalizedFeatures((*S().texts)[it->second])[d];
            dimObs[d].push_back({dj, item.correct});
            coveredDims.insert(d);
        }
        items.push_back(std::move(item));
    }

    // 计算贝叶斯后验
    User updated;
    updated.initializeDefault();
    for (int d : coveredDims) {
        const double posterior = initPosteriorMean(dimObs[d]);
        updated.setAbility(d, posterior);
        updated.setBaseAbility(d, posterior);
        updated.setQuizCount(d, static_cast<int>(dimObs[d].size()));
    }

    const time_t effective_ts = (timestamp == 0) ? time(nullptr) : static_cast<time_t>(timestamp);

    // 事务：写作答流水 + 清增量 + 落库 + 置 initialized
    SqlTransaction tx(S().db.get(), "BEGIN IMMEDIATE");
    if (!tx.ok()) return BRIDGE_ERR_GENERIC;
    bool ok = true;

    for (const auto& item : items) {
        ok = S().quizRepo->insertAttempt(S().activeUserId, item.qid, item.textId, item.correct,
                                         0, 1, static_cast<int64_t>(effective_ts));
        if (!ok) {
            LOG_ERROR("bridge: user_init_apply 写 quiz_attempts 失败 qid={}: {}", item.qid,
                      S().db->getLastError());
            break;
        }
    }

    if (ok && !coveredDims.empty()) {
        // 库内维度为 1-based（0-based 下标 + 1）
        std::vector<int> dims1Based;
        dims1Based.reserve(coveredDims.size());
        for (int d : coveredDims) dims1Based.push_back(d + 1);
        ok = S().incrementRepo->deleteByDimensions(S().activeUserId, dims1Based);
        if (!ok) {
            LOG_ERROR("bridge: user_init_apply 清理 learning_increments 失败: {}", S().db->getLastError());
        }
    }

    if (ok && !S().userRepo->saveUser(updated, S().activeUserId)) {
        LOG_ERROR("bridge: user_init_apply 落库失败");
        ok = false;
    }
    if (ok && !S().userRepo->setInitialized(S().activeUserId)) {
        LOG_ERROR("bridge: user_init_apply 置 initialized 失败");
        ok = false;
    }

    if (ok) ok = tx.commit();
    if (!ok) {
        LOG_ERROR("bridge: user_init_apply 事务失败");
        return BRIDGE_ERR_GENERIC;
    }

    S().user = std::make_unique<User>(updated);
    user_to_c(updated, out_user);
    LOG_INFO("bridge: 用户初始化完成 — user_id={}, 覆盖维度 {} 个", S().activeUserId,
             static_cast<int>(coveredDims.size()));
    return BRIDGE_OK;
    });
}

// ─── user profiles（本地多档案） ───────────────────────────────────────────────

// 未删除档案列表（按 id 升序）。返回条数；out 为空/容量不足按 0 处理（无错误码）。
extern "C" CHINESE_CORE_EXPORT int user_list(ProfileData* out, int max_count)
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    if (!out || max_count <= 0) return 0;

    const auto profiles = S().userRepo->listProfiles();
    const int n = std::min(max_count, static_cast<int>(profiles.size()));
    for (int i = 0; i < n; i++) {
        std::memset(&out[i], 0, sizeof(ProfileData));
        out[i].id = profiles[i].id;
        std::strncpy(out[i].name, profiles[i].name.c_str(), 63);
        out[i].name[63] = '\0';
        out[i].created_at = profiles[i].createdAt;
        out[i].last_used_at = profiles[i].lastUsedAt;
        out[i].deleted = profiles[i].deleted;
    }
    return n;
    });
}

extern "C" CHINESE_CORE_EXPORT int user_active_id()
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized) return 0;
    return S().activeUserId;
    });
}

extern "C" CHINESE_CORE_EXPORT int user_create(const char* name)
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    if (!name || std::strlen(name) == 0 || std::strlen(name) > 63) {
        LOG_WARN("bridge: user_create 非法档案名（空或超 63 字节）");
        return BRIDGE_ERR_GENERIC;
    }
    int newId = 0;
    if (!S().userRepo->createProfile(name, newId)) {
        LOG_ERROR("bridge: user_create 失败 name={}", name);
        return BRIDGE_ERR_GENERIC;
    }
    LOG_INFO("bridge: 已创建档案 id={} name={}", newId, name);
    return newId;
    });
}

extern "C" CHINESE_CORE_EXPORT int user_create_inherit(const char* name, int source_id)
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    if (!name || std::strlen(name) == 0 || std::strlen(name) > 63) {
        LOG_WARN("bridge: user_create_inherit 非法档案名（空或超 63 字节）");
        return BRIDGE_ERR_GENERIC;
    }
    int newId = 0;
    if (!S().userRepo->createProfileInherit(name, source_id, newId)) {
        LOG_ERROR("bridge: user_create_inherit 失败 name={} source_id={}", name, source_id);
        return BRIDGE_ERR_GENERIC;
    }
    LOG_INFO("bridge: 已创建继承档案 id={} name={} source_id={}", newId, name, source_id);
    return newId;
    });
}

extern "C" CHINESE_CORE_EXPORT int user_switch(int id)
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    if (id <= 0 || !S().userRepo->isProfileActive(id)) {
        LOG_WARN("bridge: user_switch 档案不存在或已删除 id={}", id);
        return BRIDGE_ERR_USER;
    }
    if (id == S().activeUserId) {
        S().userRepo->touchProfile(id);
        return BRIDGE_OK;
    }
    if (!loadUserForActive(id)) {
        return BRIDGE_ERR_GENERIC;
    }
    return BRIDGE_OK;
    });
}

extern "C" CHINESE_CORE_EXPORT int user_rename(int id, const char* name)
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    if (!name || std::strlen(name) == 0 || std::strlen(name) > 63) {
        LOG_WARN("bridge: user_rename 非法档案名（空或超 63 字节）");
        return BRIDGE_ERR_GENERIC;
    }
    if (!S().userRepo->renameProfile(id, name)) {
        LOG_WARN("bridge: user_rename 拒绝（档案不存在/已删除/与未删除档案重名） id={}", id);
        return BRIDGE_ERR_USER;
    }
    return BRIDGE_OK;
    });
}

extern "C" CHINESE_CORE_EXPORT int user_delete(int id)
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    if (id == S().activeUserId) {
        LOG_WARN("bridge: user_delete 拒绝删除当前档案 id={}", id);
        return BRIDGE_ERR_USER;
    }
    if (!S().userRepo->deleteProfile(id)) {
        LOG_WARN("bridge: user_delete 档案不存在或已删除 id={}", id);
        return BRIDGE_ERR_USER;
    }
    LOG_INFO("bridge: 档案已删除 id={}", id);
    return BRIDGE_OK;
    });
}
