#include "c_types.h"
#include "database/DatabaseManager.h"
#include "database/UserRepository.h"
#include "database/TextRepository.h"
#include "database/ReadingHistoryRepository.h"
#include "database/LearningIncrementRepository.h"
#include "core/RecommendationEngine.h"
#include "core/KnowledgeTracker.h"
#include "models/User.h"
#include "models/Text.h"
#include "utils/Logger.h"

#include <cstring>
#include <memory>
#include <vector>
#include <unordered_map>
#include <algorithm>

static struct {
    std::unique_ptr<DatabaseManager> db;
    std::unique_ptr<UserRepository> userRepo;
    std::unique_ptr<TextRepository> textRepo;
    std::unique_ptr<ReadingHistoryRepository> historyRepo;
    std::unique_ptr<LearningIncrementRepository> incrementRepo;
    std::unique_ptr<RecommendationEngine> engine;
    std::unique_ptr<KnowledgeTracker> tracker;
    std::unique_ptr<User> user;
    std::unique_ptr<std::vector<Text>> texts;
    std::unique_ptr<std::unordered_map<int, Text>> textIndex;
    bool initialized = false;
} g_state;

// ─── helpers ───────────────────────────────────────────────────────────────────

static void user_to_c(const User& src, UserData* dst)
{
    std::strncpy(dst->name, src.getName().c_str(), 127);
    dst->name[127] = '\0';
    for (int i = 0; i < 10; i++) {
        dst->abilities[i] = src.getAbility(i);
        dst->base_abilities[i] = src.getBaseAbility(i);
    }
    dst->last_read_time = static_cast<int64_t>(src.getLastReadTime());
}

static void c_to_user(const UserData* src, User& dst)
{
    dst.setName(std::string(src->name));
    for (int i = 0; i < 10; i++) {
        dst.setAbility(i, src->abilities[i]);
        dst.setBaseAbility(i, src->base_abilities[i]);
    }
    dst.setLastReadTime(static_cast<time_t>(src->last_read_time));
}

// ─── lifecycle ─────────────────────────────────────────────────────────────────

extern "C" int db_open(const char* db_path)
{
    // 关闭旧连接
    if (g_state.db) {
        g_state.db->close();
    }
    g_state = {};

    g_state.db = std::make_unique<DatabaseManager>();
    if (!g_state.db->open(db_path)) {
        LOG_ERROR("bridge: db_open 失败: {}", g_state.db->getLastError());
        g_state.db.reset();
        return BRIDGE_ERR_GENERIC;
    }

    g_state.userRepo = std::make_unique<UserRepository>(g_state.db.get());
    g_state.textRepo = std::make_unique<TextRepository>(g_state.db.get());
    g_state.historyRepo = std::make_unique<ReadingHistoryRepository>(g_state.db.get());
    g_state.incrementRepo = std::make_unique<LearningIncrementRepository>(g_state.db.get());

    g_state.engine = std::make_unique<RecommendationEngine>();
    g_state.user = std::make_unique<User>();
    g_state.texts = std::make_unique<std::vector<Text>>(g_state.textRepo->getAllTexts());

    // 构建 O(1) 文本索引 (修复 #8 getTextDetail O(n) 扫描)
    g_state.textIndex = std::make_unique<std::unordered_map<int, Text>>();
    for (const auto& t : *g_state.texts) {
        (*g_state.textIndex)[t.getId()] = t;
    }

    g_state.tracker = std::make_unique<KnowledgeTracker>(g_state.incrementRepo.get());

    // 加载用户或初始化默认
    if (g_state.userRepo->getUser(*g_state.user)) {
        if (g_state.user->getAverageAbility() <= 0.001) {
            g_state.user->initializeDefault();
        }
    } else {
        g_state.user->initializeDefault();
        g_state.user->setName("佚名");
    }
    g_state.tracker->applyForgettingEffect(*g_state.user, time(nullptr));
    g_state.userRepo->saveUser(*g_state.user);

    g_state.initialized = true;
    LOG_INFO("bridge: db_open 成功, {} 篇文本已加载", g_state.texts->size());
    return BRIDGE_OK;
}

extern "C" void db_close()
{
    g_state = {};
    LOG_INFO("bridge: db_close 完成");
}

// ─── user ──────────────────────────────────────────────────────────────────────

extern "C" int user_load(UserData* out)
{
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    user_to_c(*g_state.user, out);
    return BRIDGE_OK;
}

extern "C" int user_save(const UserData* in)
{
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    c_to_user(in, *g_state.user);
    if (g_state.userRepo->saveUser(*g_state.user)) {
        return BRIDGE_OK;
    }
    LOG_ERROR("bridge: user_save 失败");
    return BRIDGE_ERR_GENERIC;
}

extern "C" int user_init_default()
{
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    g_state.user->initializeDefault();
    g_state.user->setName("佚名");
    if (g_state.userRepo->saveUser(*g_state.user)) {
        return BRIDGE_OK;
    }
    return BRIDGE_ERR_GENERIC;
}

// ─── text ──────────────────────────────────────────────────────────────────────

extern "C" int text_get_count()
{
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    return static_cast<int>(g_state.texts->size());
}

extern "C" void text_get_all(TextInfo* out, int max_count)
{
    if (!g_state.initialized || !out) return;
    int n = std::min(max_count, static_cast<int>(g_state.texts->size()));
    for (int i = 0; i < n; i++) {
        const auto& t = (*g_state.texts)[i];
        out[i].id = t.getId();
        std::strncpy(out[i].title, t.getTitle().c_str(), 255);
        out[i].title[255] = '\0';
        std::strncpy(out[i].author, t.getAuthor().c_str(), 127);
        out[i].author[127] = '\0';
        std::strncpy(out[i].dynasty, t.getDynasty().c_str(), 63);
        out[i].dynasty[63] = '\0';
    }
}

extern "C" int text_get_detail(int id, TextDetail* out)
{
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    if (!out) return BRIDGE_ERR_GENERIC;

    auto it = g_state.textIndex->find(id);
    if (it == g_state.textIndex->end()) {
        return BRIDGE_ERR_TEXT;
    }

    const auto& text = it->second;
    out->id = text.getId();
    std::strncpy(out->title, text.getTitle().c_str(), 255);
    out->title[255] = '\0';
    std::strncpy(out->author, text.getAuthor().c_str(), 127);
    out->author[127] = '\0';
    std::strncpy(out->dynasty, text.getDynasty().c_str(), 63);
    out->dynasty[63] = '\0';
    std::strncpy(out->content, text.getContent().c_str(), 65535);
    out->content[65535] = '\0';
    for (int i = 0; i < 10; i++) {
        out->difficulties[i] = text.getDifficulty(i);
    }
    return BRIDGE_OK;
}

// ─── recommend ─────────────────────────────────────────────────────────────────

extern "C" void recommend(const UserData* user, int top_k,
                          int* out_ids, double* out_probs)
{
    if (!g_state.initialized || !user || !out_ids || !out_probs) return;

    User cpp_user;
    c_to_user(user, cpp_user);

    auto results = g_state.engine->recommend(cpp_user, *g_state.texts, top_k);

    for (size_t i = 0; i < results.size(); i++) {
        out_ids[i] = results[i].first;
        out_probs[i] = results[i].second;
    }
}

// ─── knowledge tracker ─────────────────────────────────────────────────────────

extern "C" int tracker_apply_read(const UserData* user, int text_id,
                                  double read_time, int64_t timestamp,
                                  UserData* out_user)
{
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;

    auto it = g_state.textIndex->find(text_id);
    if (it == g_state.textIndex->end()) return BRIDGE_ERR_TEXT;

    User cpp_user;
    c_to_user(user, cpp_user);

    g_state.tracker->applyReadEffect(cpp_user, it->second, read_time,
                                     static_cast<time_t>(timestamp));
    user_to_c(cpp_user, out_user);

    // 持久化
    g_state.userRepo->saveUser(cpp_user);
    return BRIDGE_OK;
}

extern "C" int tracker_apply_forgetting(const UserData* user, int64_t now,
                                        UserData* out_user)
{
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;

    User cpp_user;
    c_to_user(user, cpp_user);

    g_state.tracker->applyForgettingEffect(cpp_user, static_cast<time_t>(now));
    user_to_c(cpp_user, out_user);
    return BRIDGE_OK;
}

extern "C" int tracker_prune(const UserData* user, int64_t now, UserData* out_user)
{
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;

    User cpp_user;
    c_to_user(user, cpp_user);

    g_state.tracker->pruneOldIncrements(cpp_user, static_cast<time_t>(now));
    user_to_c(cpp_user, out_user);

    // 持久化修剪后的状态
    g_state.userRepo->saveUser(cpp_user);
    return BRIDGE_OK;
}
