#include <catch_amalgamated.hpp>
#include "c_types.h"
#include <string>

extern "C" {
    int db_open(const char* db_path);
    void db_close();
    int user_load(UserData* out);
    int user_save(const UserData* in);
    int user_init_default();
    int text_get_count();
    int text_get_detail(int id, TextDetail* out);
    int recommend(const UserData* user, int top_k, int* out_ids, double* out_probs, int out_ids_capacity, int out_probs_capacity);
    int tracker_apply_read(const UserData* user, int text_id, double read_time, int64_t timestamp, UserData* out_user);
    int tracker_apply_forgetting(const UserData* user, int64_t now, UserData* out_user);
    int tracker_prune(const UserData* user, int64_t now, UserData* out_user);
    int history_add_record(int text_id, double read_time, int64_t timestamp);
    int history_get_recent(int limit, ReadingRecordData* out, int max_count);
    int history_get_total_count();
    int history_get_tracked_text_ids(int* out, int max_count);
}

TEST_CASE("bridge - 未初始化时返回错误码", "[bridge][smoke]") {
    db_close();

    REQUIRE(text_get_count() == BRIDGE_ERR_NOT_INIT);

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

    REQUIRE(db_open("data/classical.db") == BRIDGE_OK);

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
