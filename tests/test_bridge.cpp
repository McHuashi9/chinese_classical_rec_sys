#include <catch_amalgamated.hpp>
#include "c_types.h"
#include <cstring>
#include <filesystem>
#include <string>

namespace fs = std::filesystem;

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
    const double u_before = user.abilities[3];

    UserData out;
    // 题目不存在
    REQUIRE(tracker_apply_quiz(&user, 999999, 0, 1000000, &out, nullptr) == BRIDGE_ERR_TEXT);

    // 题目 id=1（库中必有，dims=3,4,9，answer_index=2）：答对 → 首维能力上调，dims 覆盖维度 quiz_count 自增
    int correct = -1;
    REQUIRE(tracker_apply_quiz(&user, 1, 2, 1000000, &out, &correct) == BRIDGE_OK);
    REQUIRE(correct == 1);
    REQUIRE(out.quiz_counts[3] >= 1);
    REQUIRE(out.quiz_counts[4] >= 1);
    REQUIRE(out.quiz_counts[9] >= 1);
    REQUIRE(out.abilities[3] >= u_before - 1e-12);
    // η 不越界
    REQUIRE(out.eta >= 0.02);
    REQUIRE(out.eta <= 0.15);

    // 持久化后重开，quiz_count 仍在
    REQUIRE(user_save(&out) == BRIDGE_OK);
    db_close();
    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);
    UserData reloaded;
    REQUIRE(user_load(&reloaded) == BRIDGE_OK);
    REQUIRE(reloaded.quiz_counts[3] == out.quiz_counts[3]);

    db_close();
}

TEST_CASE("bridge - tracker_apply_quiz 答错拉低能力与参数校验", "[bridge][smoke]") {
    db_close();

    const std::string work = quizWorkDb("quiz_wrong");
    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);

    UserData user;
    REQUIRE(user_load(&user) == BRIDGE_OK);
    const double u_before = user.abilities[3];
    const double eta_before = user.eta;

    UserData out;
    // 答错（answer_index=2，故意选 0）→ 首维能力下调，η 下降
    int correct = -1;
    REQUIRE(tracker_apply_quiz(&user, 1, 0, 1000000, &out, &correct) == BRIDGE_OK);
    REQUIRE(correct == 0);
    REQUIRE(out.abilities[3] <= u_before - 1e-12);
    REQUIRE(out.eta <= eta_before + 1e-12);
    REQUIRE(out.quiz_counts[3] >= 1);

    // 非法选项被拒绝（user_choice 越界）
    REQUIRE(tracker_apply_quiz(&user, 1, -1, 1000000, &out, nullptr) == BRIDGE_ERR_GENERIC);
    REQUIRE(tracker_apply_quiz(&user, 1, 4, 1000000, &out, nullptr) == BRIDGE_ERR_GENERIC);

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
        // 每题 id 都可通过 tracker_apply_quiz 判题
    }

    // 第二题数量能被上限截断且与第一题同源
    REQUIRE(question_get_by_text(1, qs, n) >= 1);

    // 文章不存在返回错误（区别于"无题"返回 0）
    REQUIRE(question_get_by_text(999999, qs, 5) == BRIDGE_ERR_TEXT);

    // 无题文章（存在但无题）返回 0
    REQUIRE(question_get_by_text(76, qs, 5) == 0);

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
