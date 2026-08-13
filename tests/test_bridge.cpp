#include <catch_amalgamated.hpp>
#include "c_types.h"
#include <cstring>
#include <cstdlib>
#include <filesystem>
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
std::string quizWorkDb(const std::string& tag)
{
    const std::string path = std::string(TEST_DB_PATH) + "." + tag + ".db";
    fs::copy_file(TEST_DB_PATH, path, fs::copy_options::overwrite_existing);
    fs::remove(path + ".bak");
    return path;
}

extern "C" {
    int db_open(const char* db_path);
    void db_close();
    int user_load(UserData* out);
    int user_save(const UserData* in);
    int user_init_default();
    int text_get_count();
    int text_get_detail(int id, TextDetail* out);
    int text_get_translation(int id, char* out, int max_len);
    int text_get_annotations(int id, char* out, int max_len);
    int recommend(const UserData* user, int top_k, int* out_ids, double* out_probs, int out_ids_capacity, int out_probs_capacity);
    int tracker_apply_read(const UserData* user, int text_id, double read_time, int64_t timestamp, UserData* out_user);
    int tracker_apply_forgetting(const UserData* user, int64_t now, UserData* out_user);
    int tracker_prune(const UserData* user, int64_t now, UserData* out_user);
    int tracker_apply_quiz(const UserData* user, int question_id, int user_choice,
                           int64_t timestamp, UserData* out_user, int* out_correct);
    int question_get_by_text(int text_id, QuestionData* out, int max_count);
    int history_add_record(int text_id, double read_time, int64_t timestamp);
    int history_get_recent(int limit, ReadingRecordData* out, int max_count);
    int history_get_total_count();
    int history_get_tracked_text_ids(int* out, int max_count);
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
    REQUIRE(tracker_apply_read(&user, 1, 30.0, now, &out) == BRIDGE_ERR_NOT_INIT);
    REQUIRE(tracker_apply_forgetting(&user, now, &out) == BRIDGE_ERR_NOT_INIT);
    REQUIRE(tracker_prune(&user, now, &out) == BRIDGE_ERR_NOT_INIT);
    REQUIRE(tracker_apply_quiz(&user, 1, 0, now, &out, nullptr) == BRIDGE_ERR_NOT_INIT);
    REQUIRE(history_add_record(1, 30.0, now) == BRIDGE_ERR_NOT_INIT);
    REQUIRE(history_get_recent(10, records, 5) == BRIDGE_ERR_NOT_INIT);
    REQUIRE(history_get_total_count() == 0);
    REQUIRE(history_get_tracked_text_ids(out_ids, 5) == 0);
}

TEST_CASE("bridge - db_open 无效路径返回错误", "[bridge][smoke]") {
    db_close();

    int rc = db_open("/nonexistent/path/to/db.sqlite");
    REQUIRE(rc == BRIDGE_ERR_GENERIC);
}

TEST_CASE("bridge - 完整初始化链路 smoke test", "[bridge][smoke]") {
    db_close();

    REQUIRE(db_open(TEST_DB_PATH) == BRIDGE_OK);

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

    const std::string work = quizWorkDb("quiz");
    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);

    UserData user;
    REQUIRE(user_load(&user) == BRIDGE_OK);

    // 取文章 1 的第一题作判题对象（题库重灌后 id/answer 不固定，动态获取）
    QuestionData qs[1];
    REQUIRE(question_get_by_text(1, qs, 1) == 1);
    const int qid = qs[0].id;
    const std::vector<int> dims = parseDimsCsv(qs[0].dims);
    REQUIRE(dims.size() >= 1);
    const double u_before = user.abilities[dims[0]];

    UserData out;
    // 题目不存在
    REQUIRE(tracker_apply_quiz(&user, 999999, 0, 1000000, &out, nullptr) == BRIDGE_ERR_TEXT);

    // 答 choice=0（合法）→ 判题成功；对错随题库而定，能力方向与判定一致
    int correct = -1;
    REQUIRE(tracker_apply_quiz(&user, qid, 0, 1000000, &out, &correct) == BRIDGE_OK);
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
    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);
    UserData reloaded;
    REQUIRE(user_load(&reloaded) == BRIDGE_OK);
    REQUIRE(reloaded.quiz_counts[dims[0]] == out.quiz_counts[dims[0]]);

    db_close();
}

TEST_CASE("bridge - tracker_apply_quiz 答错拉低能力与参数校验", "[bridge][smoke]") {
    db_close();

    const std::string work = quizWorkDb("quiz_wrong");
    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);

    UserData user;
    REQUIRE(user_load(&user) == BRIDGE_OK);

    // 取文章 1 的第一题，探测出一个必然答错的选项（独立 user 副本试 0-3）
    QuestionData qs[1];
    REQUIRE(question_get_by_text(1, qs, 1) == 1);
    const int qid = qs[0].id;
    const std::vector<int> dims = parseDimsCsv(qs[0].dims);
    int wrong_choice = -1;
    for (int c = 0; c < 4; c++) {
        UserData probe = user;
        int correct = -1;
        UserData probeOut;
        REQUIRE(tracker_apply_quiz(&probe, qid, c, 1000000, &probeOut, &correct) == BRIDGE_OK);
        if (correct == 0) { wrong_choice = c; break; }
    }
    REQUIRE(wrong_choice >= 0);

    const double u_before = user.abilities[dims[0]];
    const double eta_before = user.eta;

    // 答错 → 首维能力下调，η 下降
    UserData out;
    int correct = -1;
    REQUIRE(tracker_apply_quiz(&user, qid, wrong_choice, 1000000, &out, &correct) == BRIDGE_OK);
    REQUIRE(correct == 0);
    REQUIRE(out.abilities[dims[0]] <= u_before - 1e-12);
    REQUIRE(out.eta <= eta_before + 1e-12);
    REQUIRE(out.quiz_counts[dims[0]] >= 1);

    // 非法选项被拒绝（user_choice 越界）
    REQUIRE(tracker_apply_quiz(&user, qid, -1, 1000000, &out, nullptr) == BRIDGE_ERR_GENERIC);
    REQUIRE(tracker_apply_quiz(&user, qid, 4, 1000000, &out, nullptr) == BRIDGE_ERR_GENERIC);

    db_close();
}

TEST_CASE("bridge - question_get_by_text 取题", "[bridge][smoke]") {
    db_close();

    REQUIRE(db_open(TEST_DB_PATH) == BRIDGE_OK);

    // 文章 1（库中必有题）：最多取 5 题
    QuestionData qs[8];
    int n = question_get_by_text(1, qs, 5);
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
    REQUIRE(question_get_by_text(1, qs, n) >= 1);

    // 文章不存在返回错误（区别于"无题"返回 0）
    REQUIRE(question_get_by_text(999999, qs, 5) == BRIDGE_ERR_TEXT);

    // 无题文章（存在但无题）返回 0：诫兄子严敦书（id=120）为新题库 4 篇零产出之一
    REQUIRE(question_get_by_text(120, qs, 5) == 0);

    // 参数校验
    REQUIRE(question_get_by_text(1, nullptr, 5) == BRIDGE_ERR_GENERIC);
    REQUIRE(question_get_by_text(1, qs, 0) == BRIDGE_ERR_GENERIC);

    db_close();
}

TEST_CASE("bridge - question_get_by_text 不暴露 answer_index", "[bridge][smoke]") {
    db_close();

    REQUIRE(db_open(TEST_DB_PATH) == BRIDGE_OK);

    QuestionData qs[5];
    const int n = question_get_by_text(1, qs, 5);
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

TEST_CASE("bridge - text_get_translation 完整链路", "[bridge][smoke]") {
    db_close();

    REQUIRE(db_open(TEST_DB_PATH) == BRIDGE_OK);

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

    REQUIRE(db_open(TEST_DB_PATH) == BRIDGE_OK);

    char buf[4096];
    REQUIRE(text_get_translation(999999, buf, sizeof(buf)) == BRIDGE_ERR_TEXT);

    db_close();
}

TEST_CASE("bridge - history 真实链路：阅读落库 → 查询倒序/截断/去重", "[bridge][smoke]") {
    db_close();

    const std::string work = quizWorkDb("hist");
    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);

    // 3 次阅读（文章 1 两次 + 文章 2 一次），时间戳刻意乱序
    UserData user, out;
    REQUIRE(user_load(&user) == BRIDGE_OK);
    REQUIRE(tracker_apply_read(&user, 1, 150.0, 1000, &out) == BRIDGE_OK);
    REQUIRE(tracker_apply_read(&user, 2, 60.0, 3000, &out) == BRIDGE_OK);
    REQUIRE(tracker_apply_read(&user, 1, 30.0, 2000, &out) == BRIDGE_OK);

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

    REQUIRE(db_open(TEST_DB_PATH) == BRIDGE_OK);

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
