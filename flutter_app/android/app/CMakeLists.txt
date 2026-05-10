cmake_minimum_required(VERSION 3.22)
project(chinese_core_android)
set(CMAKE_CXX_STANDARD 17)

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
list(APPEND CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/../../../bridge/bridge.cpp")

add_library(chinese_core SHARED ${CORE_SOURCES})
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
target_compile_definitions(chinese_core PRIVATE APP_VERSION="0.4.0")
