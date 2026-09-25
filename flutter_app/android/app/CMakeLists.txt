cmake_minimum_required(VERSION 3.22)
project(chinese_core_android)
set(CMAKE_CXX_STANDARD 17)

# 告警开关（NDK 为 Clang，告警即错误）
add_compile_options(-Wall -Wextra -Werror)

# 从 pubspec.yaml 读取版本号，唯一源
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../../../flutter_app/pubspec.yaml" _PUBSPEC)
string(REGEX MATCH "version: ([0-9]+\\.[0-9]+\\.[0-9]+)" _ ${_PUBSPEC})
set(APP_VERSION ${CMAKE_MATCH_1})

# SQLite3 static library (NDK: must define SQLITE_OS_ANDROID)
add_library(sqlite3_android STATIC
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/sqlite3/sqlite3.c
)
target_include_directories(sqlite3_android PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/sqlite3
)
target_compile_definitions(sqlite3_android PRIVATE SQLITE_OS_ANDROID=1)

# Core C++ sources (same filter as root CMakeLists.txt)
file(GLOB_RECURSE CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/*.cpp")
list(FILTER CORE_SOURCES EXCLUDE REGEX ".*main\\.cpp$")
list(FILTER CORE_SOURCES EXCLUDE REGEX ".*Command(Registry|Parser)\\.cpp$")
list(FILTER CORE_SOURCES EXCLUDE REGEX ".*/(Exit|Help|Library|Log|Read|Recommend)Command\\.cpp$")
list(FILTER CORE_SOURCES EXCLUDE REGEX ".*PathUtils\\.cpp$")
# v1.4.0 工作项 3：bridge.cpp 按域拆为 8 个 .cpp（与根 CMakeLists.txt 同步）
list(APPEND CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/../../../bridge/bridge_shared.cpp")
list(APPEND CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/../../../bridge/bridge_lifecycle.cpp")
list(APPEND CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/../../../bridge/bridge_user.cpp")
list(APPEND CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/../../../bridge/bridge_text.cpp")
list(APPEND CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/../../../bridge/bridge_tracker.cpp")
list(APPEND CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/../../../bridge/bridge_quiz.cpp")
list(APPEND CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/../../../bridge/bridge_history.cpp")
list(APPEND CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/../../../bridge/bridge_log.cpp")

add_library(chinese_core SHARED ${CORE_SOURCES})
# v1.4.0：与根 CMakeLists.txt 的 desktop target 保持一致——默认隐藏符号，
# 只有 bridge/export.h 的 CHINESE_CORE_EXPORT 显式标注的 40 个 C 符号进动态表。
# 缺这段时 bridge 的跨域共享 helper（S()/copyCString/fillQuestionRow 等）会以默认
# 可见性进入 APK 的 .so 动态符号表（桌面产物无此问题，故 verify-1「零泄漏」只在桌面成立）。
set_target_properties(chinese_core PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN YES
)
target_include_directories(chinese_core PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../include
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/spdlog-1.17.0/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/sqlite3
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../bridge
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/nowide/include
)
target_link_libraries(chinese_core PRIVATE sqlite3_android log)
add_definitions(-DSPDLOG_ACTIVE_LEVEL=SPDLOG_LEVEL_DEBUG)
target_compile_definitions(chinese_core PRIVATE __ANDROID__)
add_compile_definitions(APP_VERSION="${APP_VERSION}")
