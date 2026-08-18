#include <catch_amalgamated.hpp>
#include "c_types.h"
#include "test_helpers.h"
#include <sqlite3.h>
#include <cstring>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <set>
#include <sstream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

// UTF-8 码点索引 → 字节偏移（mark_start/mark_len 为码点语义，std::string::substr 为字节语义）
size_t cpToBytes(const std::string& s, size_t cpIndex)
{
    size_t bytes = 0, cps = 0;
    while (bytes < s.size() && cps < cpIndex) {
        const unsigned char c = static_cast<unsigned char>(s[bytes]);
        bytes += (c >= 0xF0) ? 4 : (c >= 0xE0) ? 3 : (c >= 0xC0) ? 2 : 1;
        cps++;
    }
    return bytes;
}

// 直读 questions 表取 answer_index（测试探测用，仅测试代码使用；
// FFI 层不下发 answer_index，判题只在 C++ 侧）
int quizAnswerIndex(const std::string& dbPath, int question_id)
{
    sqlite3* db = nullptr;
    if (sqlite3_open(dbPath.c_str(), &db) != SQLITE_OK) return -1;
    sqlite3_stmt* stmt = nullptr;
    int ans = -1;
    if (sqlite3_prepare_v2(db, "SELECT answer_index FROM questions WHERE id = ?", -1, &stmt, nullptr)
        == SQLITE_OK) {
        sqlite3_bind_int(stmt, 1, question_id);
        if (sqlite3_step(stmt) == SQLITE_ROW) ans = sqlite3_column_int(stmt, 0);
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return ans;
}

// 解析 dims CSV（如 "3,4,9"）→ 维度下标（0-based）
std::vector<int> parseDimsCsv(const char* csv)
{
    std::vector<int> out;
    std::istringstream ss(csv);
    std::string tok;
    while (std::getline(ss, tok, ',')) {
        if (!tok.empty()) out.push_back(std::atoi(tok.c_str()));
    }
    return out;
}

// 独立临时工作库（避免污染共享测试资产）
std::pair<std::string, std::string> quizWorkDb(const std::string& tag)
{
    return {test_helpers::makeContentDb(tag), test_helpers::makeUserDb(tag)};
}

extern "C" {
    int db_open(const char* content_path, const char* user_path);
    void db_close();
    int user_export(const char* dest_path);
    int db_get_schema_versions(int* user_version, int* content_version);
    int user_load(UserData* out);
    int user_save(const UserData* in);
    int user_init_default();
    int user_is_initialized();
    int user_init_questions(QuestionData* out, int max_count);
    int user_init_apply(const int* qids, const int* choices, int count, int64_t timestamp, UserData* out_user);
    int text_get_count();
    int text_get_detail(int id, TextDetail* out);
    int text_get_translation(int id, char* out, int max_len);
    int text_get_annotations(int id, char* out, int max_len);
    int recommend(const UserData* user, int top_k, int* out_ids, double* out_probs, int out_ids_capacity, int out_probs_capacity);
    int tracker_apply_read(const UserData* user, int text_id, double read_time, int64_t timestamp, UserData* out_user, int skip_effect);
    int tracker_apply_forgetting(const UserData* user, int64_t now, UserData* out_user);
    int tracker_prune(const UserData* user, int64_t now, UserData* out_user);
    int tracker_apply_quiz(const UserData* user, int question_id, int user_choice,
                           int64_t timestamp, UserData* out_user, int* out_correct, int is_review);
    int question_get_by_text(int text_id, QuestionData* out, int max_count, int* answered_all);
    int quiz_get_review_items(int text_id, ReviewItemData* out, int max_count);
    int quiz_get_due_review_count(int text_id);
    int quiz_get_questions_by_ids(const int* ids, int count, QuestionData* out, int max_count);
    int quiz_get_attempt_summary(int text_id, int* total, int* answered, int* wrong);
    int history_add_record(int text_id, double read_time, int64_t timestamp);
    int history_get_recent(int limit, ReadingRecordData* out, int max_count);
    int history_get_total_count();
    int history_get_tracked_text_ids(int* out, int max_count);
}

// 完成默认档案的强制初始化（固定 6 题，统一选 0；Phase 1 测试只关心初始化状态与后续可用性）
void initDefaultProfile()
{
    QuestionData qs[8];
    const int n = user_init_questions(qs, 8);
    REQUIRE(n == 6);
    int qids[6] = {0};
    int choices[6] = {0, 0, 0, 0, 0, 0};
    for (int i = 0; i < n; i++) qids[i] = qs[i].id;
    UserData out;
    REQUIRE(user_init_apply(qids, choices, n, 1700000000LL, &out) == BRIDGE_OK);
}

TEST_CASE("bridge - 未初始化时返回错误码", "[bridge][smoke]") {
    db_close();

    REQUIRE(text_get_count() == BRIDGE_ERR_NOT_INIT);

    char buf[16];
    REQUIRE(text_get_translation(1, buf, sizeof(buf)) == BRIDGE_ERR_NOT_INIT);
    REQUIRE(text_get_annotations(1, buf, sizeof(buf)) == BRIDGE_ERR_NOT_INIT);

    UserData user;
    REQUIRE(user_load(&user) == BRIDGE_ERR_NOT_INIT);

    UserData out;
    ReadingRecordData records[5];
    int out_ids[5];
    int64_t now = 1000000;

    REQUIRE(user_save(&user) == BRIDGE_ERR_NOT_INIT);
    REQUIRE(user_init_default() == BRIDGE_ERR_NOT_INIT);
    REQUIRE(tracker_apply_read(&user, 1, 30.0, now, &out, 0) == BRIDGE_ERR_NOT_INIT);
    REQUIRE(tracker_apply_forgetting(&user, now, &out) == BRIDGE_ERR_NOT_INIT);
    REQUIRE(tracker_prune(&user, now, &out) == BRIDGE_ERR_NOT_INIT);
    REQUIRE(tracker_apply_quiz(&user, 1, 0, now, &out, nullptr, 0) == BRIDGE_ERR_NOT_INIT);
    ReviewItemData ritems[2];
    int qids[2] = {1, 2};
    QuestionData qout[2];
    int t = 0, a = 0, w = 0;
    REQUIRE(quiz_get_review_items(0, ritems, 2) == BRIDGE_ERR_NOT_INIT);
    REQUIRE(quiz_get_due_review_count(0) == BRIDGE_ERR_NOT_INIT);
    REQUIRE(quiz_get_questions_by_ids(qids, 2, qout, 2) == BRIDGE_ERR_NOT_INIT);
    REQUIRE(quiz_get_attempt_summary(1, &t, &a, &w) == BRIDGE_ERR_NOT_INIT);
    REQUIRE(history_add_record(1, 30.0, now) == BRIDGE_ERR_NOT_INIT);
    REQUIRE(history_get_recent(10, records, 5) == BRIDGE_ERR_NOT_INIT);
    REQUIRE(history_get_total_count() == 0);
    REQUIRE(history_get_tracked_text_ids(out_ids, 5) == 0);
}

TEST_CASE("bridge - db_open 无效路径返回错误", "[bridge][smoke]") {
    db_close();

    int rc = db_open("/nonexistent/path/to/content.db", "/nonexistent/path/to/user.db");
    REQUIRE(rc == BRIDGE_ERR_DB_USER);
}

TEST_CASE("bridge - 损坏 user.db 返回 DB_USER 而非 DB_VERSION", "[bridge][smoke]") {
    db_close();
    const std::string content = test_helpers::makeContentDb("open_corrupt_user");
    const std::string user = test_helpers::makeUserDb("open_corrupt_user");
    {
        std::ofstream out(user, std::ios::binary);
        out << "this is not a sqlite database\n";
    }
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_ERR_DB_USER);
    db_close();
}

TEST_CASE("bridge - user_export 生成一致性 SQLite 快照", "[bridge][smoke]") {
    db_close();
    const auto [content, user] = quizWorkDb("user_export");
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);

    const std::string dest =
        test_helpers::workDir("user_export") + "/exported.db";
    std::error_code ec;
    std::filesystem::remove(dest, ec);
    REQUIRE(user_export(dest.c_str()) == BRIDGE_OK);

    auto collectTables = [](const std::string& path) {
        std::set<std::string> names;
        sqlite3* db = nullptr;
        if (sqlite3_open(path.c_str(), &db) != SQLITE_OK) return names;
        sqlite3_stmt* stmt = nullptr;
        if (sqlite3_prepare_v2(db,
                "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
                -1, &stmt, nullptr) == SQLITE_OK) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                names.insert(reinterpret_cast<const char*>(
                    sqlite3_column_text(stmt, 0)));
            }
        }
        sqlite3_finalize(stmt);
        sqlite3_close(db);
        return names;
    };

    sqlite3* db = nullptr;
    REQUIRE(sqlite3_open(dest.c_str(), &db) == SQLITE_OK);
    int version = -1;
    sqlite3_stmt* stmt = nullptr;
    REQUIRE(sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nullptr)
            == SQLITE_OK);
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        version = sqlite3_column_int(stmt, 0);
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    REQUIRE(version == 1);

    const auto sourceTables = collectTables(user);
    const auto exportedTables = collectTables(dest);
    REQUIRE(exportedTables == sourceTables);
    db_close();
}

TEST_CASE("bridge - db_get_schema_versions 返回双库版本", "[bridge][smoke]") {
    db_close();
    int uv = -1, cv = -1;
    REQUIRE(db_get_schema_versions(&uv, &cv) == BRIDGE_ERR_NOT_INIT);

    const auto [work, userPath] = quizWorkDb("schema_ver");
    REQUIRE(db_open(work.c_str(), userPath.c_str()) == BRIDGE_OK);
    REQUIRE(db_get_schema_versions(&uv, &cv) == BRIDGE_OK);
    REQUIRE(uv == 1);
    REQUIRE(cv == 1);

    db_close();
}

TEST_CASE("bridge - 完整初始化链路 smoke test", "[bridge][smoke]") {
    db_close();

    const auto [work, userPath] = quizWorkDb("direct_1");
    REQUIRE(db_open(work.c_str(), userPath.c_str()) == BRIDGE_OK);
    initDefaultProfile();

    REQUIRE(text_get_count() > 0);

    UserData user;
    REQUIRE(user_load(&user) == BRIDGE_OK);

    bool hasAbility = false;
    for (int i = 0; i < 10; i++) {
        if (user.abilities[i] > 0.0) {
            hasAbility = true;
            break;
        }
    }
    REQUIRE(hasAbility);

    TextDetail detail;
    REQUIRE(text_get_detail(1, &detail) == BRIDGE_OK);
    REQUIRE(detail.id == 1);
    REQUIRE(detail.char_count > 0);

    int out_ids[5];
    double out_probs[5];
    REQUIRE(recommend(&user, 5, out_ids, out_probs, 5, 5) == BRIDGE_OK);

    db_close();
}

TEST_CASE("bridge - tracker_apply_quiz 完整链路", "[bridge][smoke]") {
    db_close();

    const auto [work, userPath] = quizWorkDb("quiz");
    REQUIRE(db_open(work.c_str(), userPath.c_str()) == BRIDGE_OK);
    initDefaultProfile();

    UserData user;
    REQUIRE(user_load(&user) == BRIDGE_OK);

    // 取文章 1 的第一题作判题对象（题库重灌后 id/answer 不固定，动态获取）
    QuestionData qs[1];
    REQUIRE(question_get_by_text(1, qs, 1, nullptr) == 1);
    const int qid = qs[0].id;
    const std::vector<int> dims = parseDimsCsv(qs[0].dims);
    REQUIRE(dims.size() >= 1);
    const double u_before = user.abilities[dims[0]];

    UserData out;
    // 题目不存在
    REQUIRE(tracker_apply_quiz(&user, 999999, 0, 1000000, &out, nullptr, 0) == BRIDGE_ERR_TEXT);

    // 答 choice=0（合法）→ 判题成功；对错随题库而定，能力方向与判定一致
    int correct = -1;
    REQUIRE(tracker_apply_quiz(&user, qid, 0, 1000000, &out, &correct, 0) == BRIDGE_OK);
    REQUIRE(correct >= 0);
    REQUIRE(correct <= 1);
    if (correct == 1) {
        REQUIRE(out.abilities[dims[0]] >= u_before - 1e-12);
    } else {
        REQUIRE(out.abilities[dims[0]] <= u_before + 1e-12);
    }
    for (int j : dims) {
        REQUIRE(out.quiz_counts[j] >= 1);
    }
    // η 不越界
    REQUIRE(out.eta >= 0.02);
    REQUIRE(out.eta <= 0.15);

    // 持久化后重开，quiz_count 仍在
    REQUIRE(user_save(&out) == BRIDGE_OK);
    db_close();
    REQUIRE(db_open(work.c_str(), userPath.c_str()) == BRIDGE_OK);
    UserData reloaded;
    REQUIRE(user_load(&reloaded) == BRIDGE_OK);
    REQUIRE(reloaded.quiz_counts[dims[0]] == out.quiz_counts[dims[0]]);

    db_close();
}

TEST_CASE("bridge - tracker_apply_quiz 答错拉低能力与参数校验", "[bridge][smoke]") {
    db_close();

    const auto [work, userPath] = quizWorkDb("quiz_wrong");
    REQUIRE(db_open(work.c_str(), userPath.c_str()) == BRIDGE_OK);
    initDefaultProfile();

    UserData user;
    REQUIRE(user_load(&user) == BRIDGE_OK);

    // 取文章 1 的第一题，探测出一个必然答错的选项（独立 user 副本试 0-3）
    QuestionData qs[1];
    REQUIRE(question_get_by_text(1, qs, 1, nullptr) == 1);
    const int qid = qs[0].id;
    const std::vector<int> dims = parseDimsCsv(qs[0].dims);
    int wrong_choice = -1;
    for (int c = 0; c < 4; c++) {
        UserData probe = user;
        int correct = -1;
        UserData probeOut;
        REQUIRE(tracker_apply_quiz(&probe, qid, c, 1000000, &probeOut, &correct, 0) == BRIDGE_OK);
        if (correct == 0) { wrong_choice = c; break; }
    }
    REQUIRE(wrong_choice >= 0);

    const double u_before = user.abilities[dims[0]];
    const double eta_before = user.eta;

    // 答错 → 首维能力下调，η 下降
    UserData out;
    int correct = -1;
    REQUIRE(tracker_apply_quiz(&user, qid, wrong_choice, 1000000, &out, &correct, 0) == BRIDGE_OK);
    REQUIRE(correct == 0);
    REQUIRE(out.abilities[dims[0]] <= u_before - 1e-12);
    REQUIRE(out.eta <= eta_before + 1e-12);
    REQUIRE(out.quiz_counts[dims[0]] >= 1);

    // 非法选项被拒绝（user_choice 越界）
    REQUIRE(tracker_apply_quiz(&user, qid, -1, 1000000, &out, nullptr, 0) == BRIDGE_ERR_GENERIC);
    REQUIRE(tracker_apply_quiz(&user, qid, 4, 1000000, &out, nullptr, 0) == BRIDGE_ERR_GENERIC);

    db_close();
}

TEST_CASE("bridge - question_get_by_text 取题", "[bridge][smoke]") {
    db_close();

    const auto [work, userPath] = quizWorkDb("direct_2");
    // 新题库所有文章都有题（断句题每篇 1 题），因此额外插入一篇无题文章，
    // 专门验证“文章存在但无题 → 返回 0”的降级路径。
    {
        sqlite3* db = nullptr;
        REQUIRE(sqlite3_open(work.c_str(), &db) == SQLITE_OK);
        char* err = nullptr;
        REQUIRE(sqlite3_exec(db,
            "INSERT INTO classical_text(id, title, content) "
            "VALUES(100000, '无题测试', '测试内容');",
            nullptr, nullptr, &err) == SQLITE_OK);
        sqlite3_free(err);
        sqlite3_close(db);
    }
    REQUIRE(db_open(work.c_str(), userPath.c_str()) == BRIDGE_OK);
    initDefaultProfile();

    // 文章 1（库中必有题）：最多取 5 题
    QuestionData qs[8];
    int n = question_get_by_text(1, qs, 5, nullptr);
    REQUIRE(n >= 1);
    REQUIRE(n <= 5);
    for (int i = 0; i < n; i++) {
        REQUIRE(qs[i].id > 0);
        REQUIRE(std::string(qs[i].stem).size() > 0);
        REQUIRE(std::string(qs[i].options[0]).size() > 0);
        REQUIRE(std::string(qs[i].options[1]).size() > 0);
        REQUIRE(std::string(qs[i].options[2]).size() > 0);
        REQUIRE(std::string(qs[i].options[3]).size() > 0);
        REQUIRE(std::string(qs[i].dims).size() > 0);
        REQUIRE(qs[i].difficulty >= 0.0);
        REQUIRE(qs[i].difficulty <= 1.0);
        // 划线语境一致性：无 context 时区间必须为空；有 context 时区间在界内
        // 且划出的字串与题干「X」中的词一致
        const std::string ctx(qs[i].context);
        if (ctx.empty()) {
            REQUIRE(qs[i].mark_start == -1);
            REQUIRE(qs[i].mark_len == 0);
        } else {
            REQUIRE(qs[i].mark_start >= 0);
            REQUIRE(qs[i].mark_len > 0);
            REQUIRE(qs[i].mark_start + qs[i].mark_len <= static_cast<int>(ctx.size()));
            const std::string stem(qs[i].stem);
            const size_t b = stem.find("「"), e = stem.find("」");
            if (b != std::string::npos && e != std::string::npos && e > b) {
                // 「」各占 3 字节 UTF-8，跳过括号取词
                const std::string word = stem.substr(b + 3, e - b - 3);
                const size_t sB = cpToBytes(ctx, qs[i].mark_start);
                const size_t eB = cpToBytes(ctx, qs[i].mark_start + qs[i].mark_len);
                REQUIRE(ctx.substr(sB, eB - sB) == word);
            }
        }
        // 每题 id 都可通过 tracker_apply_quiz 判题
    }

    // 第二题数量能被上限截断且与第一题同源
    REQUIRE(question_get_by_text(1, qs, n, nullptr) >= 1);

    // 文章不存在返回错误（区别于"无题"返回 0）
    REQUIRE(question_get_by_text(999999, qs, 5, nullptr) == BRIDGE_ERR_TEXT);

    // 无题文章（存在但无题）返回 0：使用上方插入的无题测试文章
    int answered_all = -1;
    REQUIRE(question_get_by_text(100000, qs, 5, &answered_all) == 0);
    REQUIRE(answered_all == 0);

    // 参数校验
    REQUIRE(question_get_by_text(1, nullptr, 5, nullptr) == BRIDGE_ERR_GENERIC);
    REQUIRE(question_get_by_text(1, qs, 0, nullptr) == BRIDGE_ERR_GENERIC);

    db_close();
}

TEST_CASE("bridge - question_get_by_text 不暴露 answer_index", "[bridge][smoke]") {
    db_close();

    const auto [work, userPath] = quizWorkDb("direct_3");
    REQUIRE(db_open(work.c_str(), userPath.c_str()) == BRIDGE_OK);
    initDefaultProfile();

    QuestionData qs[5];
    const int n = question_get_by_text(1, qs, 5, nullptr);
    REQUIRE(n >= 1);
    // QuestionData 无 answer_index 字段——编译期保证不暴露；
    // 运行时验证：取到的题干/选项不含答案下标痕迹（选项文本非 "A"/"B" 单字符）
    for (int i = 0; i < n; i++) {
        for (int k = 0; k < 4; k++) {
            const std::string opt = qs[i].options[k];
            REQUIRE(opt != "A");
            REQUIRE(opt != "B");
            REQUIRE(opt != "C");
            REQUIRE(opt != "D");
        }
    }

    db_close();
}

TEST_CASE("bridge - 取题排除已答 + 随机轮换 + answered_all（测验闭环）", "[bridge][smoke]") {
    db_close();

    const auto [work, userPath] = quizWorkDb("quiz_closure");
    REQUIRE(db_open(work.c_str(), userPath.c_str()) == BRIDGE_OK);
    initDefaultProfile();

    UserData user;
    REQUIRE(user_load(&user) == BRIDGE_OK);

    // 固定种子：连续两次取题批次相同（可复现）
    QuestionData batch1[5], batch2[5];
    int answered_all = -1;
    const int n1 = question_get_by_text(1, batch1, 5, &answered_all);
    REQUIRE(n1 >= 1);
    REQUIRE(answered_all == 0);
    REQUIRE(question_get_by_text(1, batch1, n1, nullptr) == n1);
    // 注意：第二次取题若文章 1 题数 ≤ 5 会直接答完——仅在剩余足够时校验种子可复现
    int total = -1, answered = -1, wrong = -1;
    REQUIRE(quiz_get_attempt_summary(1, &total, &answered, &wrong) == BRIDGE_OK);
    if (total > n1) {
        REQUIRE(question_get_by_text(1, batch2, n1, nullptr) == n1);
        for (int i = 0; i < n1; i++) REQUIRE(batch1[i].id == batch2[i].id);
    }

    // 逐批答完全部题（choice=0）：每批作答后剩余题随机轮换，直至 answered_all=1
    const int64_t ts = static_cast<int64_t>(time(nullptr));
    int rounds = 0;
    std::set<int> seen;
    while (rounds < 100) {
        UserData out;
        int a = -1;
        const int n = question_get_by_text(1, batch1, 5, &a);
        REQUIRE(n >= 0);
        if (n == 0) {
            REQUIRE(a == 1);
            break;
        }
        // 排除已答生效：跨批次不重复
        for (int i = 0; i < n; i++) {
            REQUIRE(seen.insert(batch1[i].id).second);
            int correct = -1;
            REQUIRE(tracker_apply_quiz(&user, batch1[i].id, 0, ts, &out, &correct, 0) == BRIDGE_OK);
            user = out;
        }
        rounds++;
    }
    REQUIRE(rounds > 0);
    // 全部答完：summary answered == total
    REQUIRE(quiz_get_attempt_summary(1, &total, &answered, &wrong) == BRIDGE_OK);
    REQUIRE(answered == total);

    db_close();
}

TEST_CASE("bridge - 复习通道：错题入队/到期过滤/按 id 取题/is_review 无效应（测验闭环）", "[bridge][smoke]") {
    db_close();

    const auto [work, userPath] = quizWorkDb("quiz_review");
    REQUIRE(db_open(work.c_str(), userPath.c_str()) == BRIDGE_OK);
    initDefaultProfile();

    UserData user;
    REQUIRE(user_load(&user) == BRIDGE_OK);

    // 取文章 1 的一题 + 答案下标（测试侧直读 DB 探测，无副作用）
    QuestionData qs[1];
    REQUIRE(question_get_by_text(1, qs, 1, nullptr) == 1);
    const int qid = qs[0].id;
    const std::vector<int> dims = parseDimsCsv(qs[0].dims);
    REQUIRE(dims.size() >= 1);
    const int d0 = dims[0];
    const int ans_idx = quizAnswerIndex(work, qid);
    REQUIRE(ans_idx >= 0);
    const int right_choice = ans_idx;
    const int wrong_choice = (ans_idx + 1) % 4;

    const int64_t now = static_cast<int64_t>(time(nullptr));
    UserData out;
    int correct = -1;

    // 答错 → review_items 入队，next_review_at = answered_at + 3 天
    REQUIRE(tracker_apply_quiz(&user, qid, wrong_choice, now, &out, &correct, 0) == BRIDGE_OK);
    REQUIRE(correct == 0);
    user = out;

    // 未到期：复习列表为空（3 天后才到期）
    ReviewItemData items[8];
    REQUIRE(quiz_get_review_items(0, items, 8) == 0);
    REQUIRE(quiz_get_due_review_count(0) == 0);

    // 用过去时间戳再答错（模拟 3 天前）→ 已到期，wrong_count 累计
    const int64_t past = now - 4LL * 24 * 3600;
    REQUIRE(tracker_apply_quiz(&user, qid, wrong_choice, past, &out, &correct, 0) == BRIDGE_OK);
    user = out;
    REQUIRE(quiz_get_review_items(0, items, 8) == 1);
    REQUIRE(items[0].question_id == qid);
    REQUIRE(items[0].text_id == 1);
    REQUIRE(items[0].wrong_count == 2);
    REQUIRE(items[0].next_review_at <= now);
    // 到期总数与列表同源（COUNT 聚合，徽标通道不受列表上限截断）
    REQUIRE(quiz_get_due_review_count(0) == 1);
    REQUIRE(quiz_get_due_review_count(1) == 1);
    REQUIRE(quiz_get_due_review_count(2) == 0);
    // 按篇过滤
    REQUIRE(quiz_get_review_items(2, items, 8) == 0);
    REQUIRE(quiz_get_review_items(1, items, 8) == 1);

    // 按 id 取题通道：复习题已被排除已答，但独立通道可取回
    const int ids[1] = {qid};
    QuestionData rq[1];
    REQUIRE(quiz_get_questions_by_ids(ids, 1, rq, 1) == 1);
    REQUIRE(rq[0].id == qid);

    // 复习作答（is_review=1，答对）→ 无答题效应：能力/eta/quiz_count 均不变
    const double u_before = user.abilities[d0];
    const int qc_before = user.quiz_counts[d0];
    const double eta_before = user.eta;
    UserData outReview;
    REQUIRE(tracker_apply_quiz(&user, qid, right_choice, past, &outReview, &correct, 1) == BRIDGE_OK);
    REQUIRE(correct == 1);
    REQUIRE(outReview.abilities[d0] == u_before);
    REQUIRE(outReview.quiz_counts[d0] == qc_before);
    REQUIRE(outReview.eta == eta_before);
    // streak=1 → 下次到期在将来 → 到期列表为空
    REQUIRE(quiz_get_review_items(0, items, 8) == 0);
    REQUIRE(quiz_get_due_review_count(0) == 0);

    // 连续答对 2 次（累计 streak=3）→ 从复习队列移除
    REQUIRE(tracker_apply_quiz(&user, qid, right_choice, past, &outReview, &correct, 1) == BRIDGE_OK);
    REQUIRE(tracker_apply_quiz(&user, qid, right_choice, past, &outReview, &correct, 1) == BRIDGE_OK);
    REQUIRE(quiz_get_review_items(1, items, 8) == 0);
    // 移除后按 id 仍可取题（数据完整性不受影响）
    REQUIRE(quiz_get_questions_by_ids(ids, 1, rq, 1) == 1);

    // 复习再答错 → streak 清零、重新入队（3 天后到期）
    REQUIRE(tracker_apply_quiz(&user, qid, wrong_choice, past, &outReview, &correct, 1) == BRIDGE_OK);
    REQUIRE(correct == 0);
    REQUIRE(quiz_get_review_items(1, items, 8) == 1);
    REQUIRE(items[0].correct_streak == 0);

    // 正式测验答对在队错题 → 从 review_items 移除（视为已掌握）
    REQUIRE(tracker_apply_quiz(&user, qid, right_choice, past, &out, &correct, 0) == BRIDGE_OK);
    REQUIRE(correct == 1);
    REQUIRE(quiz_get_review_items(1, items, 8) == 0);

    // 参数校验
    REQUIRE(quiz_get_review_items(0, nullptr, 8) == BRIDGE_ERR_GENERIC);
    REQUIRE(quiz_get_questions_by_ids(nullptr, 1, rq, 1) == BRIDGE_ERR_GENERIC);

    db_close();
}

TEST_CASE("bridge - 流水事务失败时答题效应一并回滚（防双计）", "[bridge][smoke]") {
    db_close();
    const auto [work, userPath] = quizWorkDb("quiz_txn_rollback");
    REQUIRE(db_open(work.c_str(), userPath.c_str()) == BRIDGE_OK);
    initDefaultProfile();
    // 预埋失败触发器：review_items 插入即 ABORT（模拟事务中途失败，触发器建在 user.db）
    {
        sqlite3* db = nullptr;
        REQUIRE(sqlite3_open(userPath.c_str(), &db) == SQLITE_OK);
        char* err = nullptr;
        REQUIRE(sqlite3_exec(db,
            "CREATE TRIGGER fail_review_insert BEFORE INSERT ON review_items "
            "BEGIN SELECT RAISE(ABORT, 'test: force txn failure'); END",
            nullptr, nullptr, &err) == SQLITE_OK);
        sqlite3_free(err);
        sqlite3_close(db);
    }

    UserData user;
    REQUIRE(user_load(&user) == BRIDGE_OK);
    QuestionData qs[1];
    REQUIRE(question_get_by_text(1, qs, 1, nullptr) == 1);
    const int qid = qs[0].id;
    const std::vector<int> dims = parseDimsCsv(qs[0].dims);
    REQUIRE(!dims.empty());
    const int d0 = dims[0];
    const int ans_idx = quizAnswerIndex(work, qid);
    REQUIRE(ans_idx >= 0);
    const int wrong_choice = (ans_idx + 1) % 4;
    const double ability_before = user.abilities[d0];
    const int qc_before = user.quiz_counts[d0];

    UserData out;
    int correct = -1;
    const int64_t now = static_cast<int64_t>(time(nullptr));
    // 事务失败 → GENERIC（不静默成功）
    REQUIRE(tracker_apply_quiz(&user, qid, wrong_choice, now, &out, &correct, 0) == BRIDGE_ERR_GENERIC);

    // 效应未落库：能力/quiz_count 与作答前一致（重试不会双计）
    UserData reloaded;
    REQUIRE(user_load(&reloaded) == BRIDGE_OK);
    REQUIRE(reloaded.abilities[d0] == Catch::Approx(ability_before));
    REQUIRE(reloaded.quiz_counts[d0] == qc_before);
    // 流水未写入（事务整体回滚）
    sqlite3* db = nullptr;
    REQUIRE(sqlite3_open(userPath.c_str(), &db) == SQLITE_OK);
    sqlite3_stmt* stmt = nullptr;
    int attempts = -1;
    if (sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM quiz_attempts", -1, &stmt, nullptr) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) attempts = sqlite3_column_int(stmt, 0);
        sqlite3_finalize(stmt);
    }
    sqlite3_close(db);
    REQUIRE(attempts == 6);  // 仅初始化题 6 条，普通答题流水随事务回滚

    db_close();
}

TEST_CASE("bridge - 内容库缺 questions 表：db_open 拒绝", "[bridge][smoke]") {
    db_close();
    const auto [work, userPath] = quizWorkDb("no_questions");
    // 从纯内容库副本删掉 questions 表，模拟损坏/不完整内容包
    {
        sqlite3* db = nullptr;
        REQUIRE(sqlite3_open(work.c_str(), &db) == SQLITE_OK);
        char* err = nullptr;
        REQUIRE(sqlite3_exec(db, "DROP TABLE questions", nullptr, nullptr, &err) == SQLITE_OK);
        sqlite3_free(err);
        sqlite3_close(db);
    }
    REQUIRE(db_open(work.c_str(), userPath.c_str()) == BRIDGE_ERR_DB_CONTENT);

    db_close();
}

TEST_CASE("bridge - quiz_get_attempt_summary 摘要计数", "[bridge][smoke]") {
    db_close();

    const auto [work, userPath] = quizWorkDb("quiz_summary");
    REQUIRE(db_open(work.c_str(), userPath.c_str()) == BRIDGE_OK);
    initDefaultProfile();

    int total = -1, answered = -1, wrong = -1;
    REQUIRE(quiz_get_attempt_summary(1, &total, &answered, &wrong) == BRIDGE_OK);
    REQUIRE(total > 0);
    REQUIRE(answered == 0);
    REQUIRE(wrong == 0);

    // 答错一题 → answered/wrong 各 +1
    UserData user;
    REQUIRE(user_load(&user) == BRIDGE_OK);
    QuestionData qs[1];
    REQUIRE(question_get_by_text(1, qs, 1, nullptr) == 1);
    UserData out;
    int correct = -1;
    REQUIRE(tracker_apply_quiz(&user, qs[0].id, 0, static_cast<int64_t>(time(nullptr)),
                               &out, &correct, 0) == BRIDGE_OK);
    REQUIRE(quiz_get_attempt_summary(1, &total, &answered, &wrong) == BRIDGE_OK);
    REQUIRE(answered == 1);
    REQUIRE(wrong == (correct == 0 ? 1 : 0));

    db_close();
}

TEST_CASE("bridge - text_get_translation 完整链路", "[bridge][smoke]") {
    db_close();

    const auto [work, userPath] = quizWorkDb("direct_4");
    REQUIRE(db_open(work.c_str(), userPath.c_str()) == BRIDGE_OK);
    initDefaultProfile();

    char buf[65536];
    int rc = text_get_translation(1, buf, sizeof(buf));
    REQUIRE(rc == BRIDGE_OK);
    REQUIRE(std::string(buf).size() > 0);

    char small[4];
    rc = text_get_translation(1, small, 4);
    REQUIRE(rc == BRIDGE_OK);
    REQUIRE(std::string(small).size() == 3);

    db_close();
}

TEST_CASE("bridge - text_get_translation 不存在 id 返回错误", "[bridge][smoke]") {
    db_close();

    const auto [work, userPath] = quizWorkDb("direct_5");
    REQUIRE(db_open(work.c_str(), userPath.c_str()) == BRIDGE_OK);
    initDefaultProfile();

    char buf[4096];
    REQUIRE(text_get_translation(999999, buf, sizeof(buf)) == BRIDGE_ERR_TEXT);

    db_close();
}

TEST_CASE("bridge - history 真实链路：阅读落库 → 查询倒序/截断/去重", "[bridge][smoke]") {
    db_close();

    const auto [work, userPath] = quizWorkDb("hist");
    REQUIRE(db_open(work.c_str(), userPath.c_str()) == BRIDGE_OK);
    initDefaultProfile();

    // 3 次阅读（文章 1 两次 + 文章 2 一次），时间戳刻意乱序
    UserData user, out;
    REQUIRE(user_load(&user) == BRIDGE_OK);
    REQUIRE(tracker_apply_read(&user, 1, 150.0, 1000, &out, 0) == BRIDGE_OK);
    REQUIRE(tracker_apply_read(&user, 2, 60.0, 3000, &out, 0) == BRIDGE_OK);
    REQUIRE(tracker_apply_read(&user, 1, 30.0, 2000, &out, 0) == BRIDGE_OK);

    REQUIRE(history_get_total_count() == 3);

    // 倒序：text 2 → text 1(t=2000) → text 1(t=1000)
    ReadingRecordData recs[8];
    int n = history_get_recent(10, recs, 8);
    REQUIRE(n == 3);
    REQUIRE(recs[0].text_id == 2);
    REQUIRE(recs[0].read_time == 60.0);
    REQUIRE(recs[1].text_id == 1);
    REQUIRE(recs[1].read_time == 30.0);
    REQUIRE(recs[2].text_id == 1);
    REQUIRE(recs[2].read_time == 150.0);
    REQUIRE(recs[2].timestamp == 1000);

    // limit 截断（插 3 取 2）
    REQUIRE(history_get_recent(2, recs, 8) == 2);
    // 输出容量截断
    REQUIRE(history_get_recent(10, recs, 1) == 1);
    // out 为 null → 桥约定返回 NOT_INIT
    REQUIRE(history_get_recent(10, nullptr, 8) == BRIDGE_ERR_NOT_INIT);

    // 独立 add_record 也可入链
    REQUIRE(history_add_record(5, 90.0, 4000) == BRIDGE_OK);
    REQUIRE(history_get_total_count() == 4);
    REQUIRE(history_get_recent(1, recs, 8) == 1);
    REQUIRE(recs[0].text_id == 5);

    // tracked ids：同文去重（文章 1 只出现一次），插入顺序 1, 2
    int ids[8];
    n = history_get_tracked_text_ids(ids, 8);
    REQUIRE(n == 2);
    REQUIRE(ids[0] == 1);
    REQUIRE(ids[1] == 2);
    // 容量截断
    REQUIRE(history_get_tracked_text_ids(ids, 1) == 1);

    db_close();
}

TEST_CASE("bridge - text_get_annotations 完整链路", "[bridge][smoke]") {
    db_close();

    const auto [work, userPath] = quizWorkDb("direct_6");
    REQUIRE(db_open(work.c_str(), userPath.c_str()) == BRIDGE_OK);
    initDefaultProfile();

    char buf[65536];
    int rc = text_get_annotations(1, buf, sizeof(buf));
    REQUIRE(rc == BRIDGE_OK);
    REQUIRE(std::string(buf).size() > 0);
    REQUIRE(std::string(buf).rfind("〔1〕", 0) == 0);  // 以 〔1〕 开头

    // 截断：小缓冲只写 max_len-1 字节并补 \0
    char small[8];
    rc = text_get_annotations(1, small, 8);
    REQUIRE(rc == BRIDGE_OK);
    REQUIRE(std::string(small).size() == 7);

    // 不存在的 id 返回错误
    REQUIRE(text_get_annotations(999999, buf, sizeof(buf)) == BRIDGE_ERR_TEXT);

    // 参数校验
    REQUIRE(text_get_annotations(1, nullptr, 64) == BRIDGE_ERR_GENERIC);
    REQUIRE(text_get_annotations(1, buf, 0) == BRIDGE_ERR_GENERIC);

    db_close();
}
