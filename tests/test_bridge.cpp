#include <catch_amalgamated.hpp>
#include "c_types.h"
#include <string>

extern "C" {
    int db_open(const char* db_path);
    void db_close();
    int user_load(UserData* out);
    int text_get_count();
    int text_get_detail(int id, TextDetail* out);
    int recommend(const UserData* user, int top_k, int* out_ids, double* out_probs);
}

TEST_CASE("bridge - 未初始化时返回错误码", "[bridge][smoke]") {
    db_close();

    REQUIRE(text_get_count() == BRIDGE_ERR_NOT_INIT);

    UserData user;
    REQUIRE(user_load(&user) == BRIDGE_ERR_NOT_INIT);
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

    int out_ids[5];
    double out_probs[5];
    REQUIRE(recommend(&user, 5, out_ids, out_probs) == BRIDGE_OK);

    db_close();
}
