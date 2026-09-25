// 桥层推荐与知识追踪域（v1.4.0 工作项 3）：recommend / tracker_apply_read /
// tracker_apply_forgetting / tracker_prune，共 4 个导出符号。
//
// 工作项 2：tracker_apply_read 的「阅读效应 + 历史写入 + 落库同事务」编排保留在桥层
// （仓储已现成），事务走 SqlTransaction(DatabaseManager*)，桥层不再直接取原始连接。

#include "bridge_internal.h"

#include <algorithm>
#include <cstdint>

extern "C" CHINESE_CORE_EXPORT int recommend(const UserData* user, int top_k,
                           int* out_ids, double* out_probs,
                           int out_ids_capacity, int out_probs_capacity)
{
    return bridge_guard(g_mtx, [&] {
    const int initRc = requireInitialized();
    if (initRc != BRIDGE_OK) return initRc;
    if (!user || !out_ids || !out_probs) return BRIDGE_ERR_GENERIC;

    User cpp_user;
    c_to_user(user, cpp_user);

    auto results = S().engine->recommend(cpp_user, *S().texts, top_k);

    size_t n = results.size();
    if (static_cast<int>(n) > out_ids_capacity) n = out_ids_capacity;
    if (static_cast<int>(n) > out_probs_capacity) n = out_probs_capacity;
    for (size_t i = 0; i < n; i++) {
        out_ids[i] = results[i].first;
        out_probs[i] = results[i].second;
    }
    LOG_INFO("bridge: 推荐完成 — 返回 {} 篇 (top_k={})", results.size(), top_k);
    return BRIDGE_OK;
    });
}

extern "C" CHINESE_CORE_EXPORT int tracker_apply_read(const UserData* user, int text_id,
                                   double read_time, int64_t timestamp,
                                   UserData* out_user, int skip_effect)
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    if (skip_effect == 0) {
        const int initRc = requireInitialized();
        if (initRc != BRIDGE_OK) return initRc;
    }
    if (!user || !out_user) return BRIDGE_ERR_GENERIC;

    auto it = S().textIndex->find(text_id);
    if (it == S().textIndex->end()) return BRIDGE_ERR_TEXT;

    User cpp_user;
    c_to_user(user, cpp_user);

    time_t effective_ts = (timestamp == 0) ? time(nullptr) : static_cast<time_t>(timestamp);
    // R7：阅读效应 + 历史写入 + 落库同事务；失败回滚，避免"效应已应用但历史没写"或反之
    SqlTransaction tx(S().db.get(), "BEGIN");
    if (!tx.ok()) return BRIDGE_ERR_GENERIC;
    bool ok = true;

    if (skip_effect == 0) {
        S().tracker->applyReadEffect(cpp_user, (*S().texts)[it->second], read_time,
                                     effective_ts);
        user_to_c(cpp_user, out_user);
    } else {
        // skip_effect=1：只记录阅读历史/已读，不应用能力效应
        user_to_c(cpp_user, out_user);
    }

    ok = S().historyRepo->markAsTracked(S().activeUserId, text_id);
    if (ok) ok = S().historyRepo->addRecord(S().activeUserId, text_id, read_time, effective_ts);
    if (ok && skip_effect == 0) {
        ok = S().userRepo->saveUser(cpp_user, S().activeUserId);
        if (!ok) LOG_ERROR("bridge: 阅读效应落库失败 text_id={}", text_id);
    }
    if (ok) ok = tx.commit();
    if (!ok) {
        LOG_ERROR("bridge: tracker_apply_read 事务失败 text_id={}", text_id);
        return BRIDGE_ERR_GENERIC;
    }

    if (skip_effect == 0) {
        S().user = std::make_unique<User>(cpp_user);
        LOG_INFO("bridge: 知识追踪完成 — text_id={}, read_time={:.1f}s, avg_ability={:.3f}→{:.3f}",
                 text_id, read_time, S().user->getAverageAbility(), cpp_user.getAverageAbility());
    } else {
        LOG_INFO("bridge: 初始化阅读记录完成 — text_id={}, read_time={:.1f}s（无能力效应）",
                 text_id, read_time);
    }
    return BRIDGE_OK;
    });
}

extern "C" CHINESE_CORE_EXPORT int tracker_apply_forgetting(const UserData* user, int64_t now,
                                         UserData* out_user)
{
    return bridge_guard(g_mtx, [&] {
    const int initRc = requireInitialized();
    if (initRc != BRIDGE_OK) return initRc;
    if (!user || !out_user) return BRIDGE_ERR_GENERIC;

    User cpp_user;
    c_to_user(user, cpp_user);

    S().tracker->applyForgettingEffect(cpp_user, static_cast<time_t>(now));
    user_to_c(cpp_user, out_user);
    return BRIDGE_OK;
    });
}

extern "C" CHINESE_CORE_EXPORT int tracker_prune(const UserData* user, int64_t now, UserData* out_user)
{
    return bridge_guard(g_mtx, [&] {
    const int initRc = requireInitialized();
    if (initRc != BRIDGE_OK) return initRc;
    if (!user || !out_user) return BRIDGE_ERR_GENERIC;

    User cpp_user;
    c_to_user(user, cpp_user);

    S().tracker->pruneOldIncrements(cpp_user, static_cast<time_t>(now));
    user_to_c(cpp_user, out_user);

    // 持久化修剪后的状态
    S().userRepo->saveUser(cpp_user, S().activeUserId);
    S().user = std::make_unique<User>(cpp_user);
    return BRIDGE_OK;
    });
}
