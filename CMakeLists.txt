cmake_minimum_required(VERSION 3.28)
project(chinese_classical_rec_sys)

# 设置 C++ 标准
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# MSVC 编译选项（UTF-8 编码支持）
if(MSVC)
    add_compile_options(/utf-8)
endif()

# 包含头文件目录
include_directories(${CMAKE_SOURCE_DIR}/include)

# 添加 spdlog 日志库（仅头文件）
include_directories(${CMAKE_SOURCE_DIR}/third_party/spdlog-1.17.0/include)

# 添加 Boost.Nowide 库（用于跨平台 UTF-8 编码支持）
# Windows 上需要编译源文件来实现 console buffer 和全局 cin/cout/cerr 对象
# 使用 standalone 模式避免 Boost 依赖
if(WIN32)
    add_library(nowide_static STATIC
        ${CMAKE_SOURCE_DIR}/third_party/nowide/src/console_buffer.cpp
        ${CMAKE_SOURCE_DIR}/third_party/nowide/src/iostream.cpp
    )
    target_include_directories(nowide_static PUBLIC
        ${CMAKE_SOURCE_DIR}/third_party/nowide/include
        ${CMAKE_SOURCE_DIR}/third_party/nowide/src
    )
else()
    # 非 Windows 平台，nowide 是 header-only
    include_directories(${CMAKE_SOURCE_DIR}/third_party/nowide/include)
endif()

# Windows 平台启用 spdlog 宽字符文件名支持
if(WIN32)
    add_compile_definitions(SPDLOG_WCHAR_FILENAMES)
endif()

# 静态编译 SQLite3
add_library(sqlite3_static STATIC
    ${CMAKE_SOURCE_DIR}/third_party/sqlite3/sqlite3.c
)
target_include_directories(sqlite3_static PUBLIC
    ${CMAKE_SOURCE_DIR}/third_party/sqlite3
)

# ─── 核心逻辑静态库 ───────────────────────────────────────────────────────────
file(GLOB_RECURSE LIB_SOURCES "src/*.cpp")
list(FILTER LIB_SOURCES EXCLUDE REGEX ".*main\\.cpp$")
list(FILTER LIB_SOURCES EXCLUDE REGEX ".*/Command(Registry|Parser)\\.cpp$")
list(FILTER LIB_SOURCES EXCLUDE REGEX ".*/(Exit|Help|Library|Log|Read|Recommend)Command\\.cpp$")
list(FILTER LIB_SOURCES EXCLUDE REGEX ".*/PathUtils\\.cpp$")
add_library(chinese_classical_lib STATIC ${LIB_SOURCES})

# 设置 PUBLIC 包含目录，使链接此库的目标自动获得头文件路径
target_include_directories(chinese_classical_lib PUBLIC
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/third_party/spdlog-1.17.0/include
)

# 链接 SQLite3
target_link_libraries(chinese_classical_lib PUBLIC sqlite3_static)

# Windows 平台链接 nowide（包含 cin/cout/cerr 全局对象定义）
if(WIN32)
    target_link_libraries(chinese_classical_lib PUBLIC nowide_static)
endif()

# ─── Flutter FFI 共享库 (chinese_core_shared) ──────────────────────────────────

file(GLOB_RECURSE CORE_SOURCES "src/*.cpp")
list(FILTER CORE_SOURCES EXCLUDE REGEX ".*main\\.cpp$")
list(FILTER CORE_SOURCES EXCLUDE REGEX ".*/Command(Registry|Parser)\\.cpp$")
list(FILTER CORE_SOURCES EXCLUDE REGEX ".*/(Exit|Help|Library|Log|Read|Recommend)Command\\.cpp$")
list(FILTER CORE_SOURCES EXCLUDE REGEX ".*/PathUtils\\.cpp$")
list(APPEND CORE_SOURCES "bridge/bridge.cpp")

add_library(chinese_core SHARED ${CORE_SOURCES})
target_include_directories(chinese_core PUBLIC
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/third_party/spdlog-1.17.0/include
    ${CMAKE_SOURCE_DIR}/third_party/sqlite3
    ${CMAKE_SOURCE_DIR}/bridge
)
if(WIN32)
    target_include_directories(chinese_core PUBLIC
        ${CMAKE_SOURCE_DIR}/third_party/nowide/include
        ${CMAKE_SOURCE_DIR}/third_party/nowide/src
    )
    target_compile_definitions(chinese_core PRIVATE SPDLOG_WCHAR_FILENAMES)
    target_link_libraries(chinese_core PRIVATE nowide_static)
else()
    target_include_directories(chinese_core PUBLIC
        ${CMAKE_SOURCE_DIR}/third_party/nowide/include
    )
endif()

target_link_libraries(chinese_core PRIVATE sqlite3_static)

# Linux: 确保 SQLite3 以 -fPIC 编译（共享库必需）
set_target_properties(sqlite3_static PROPERTIES POSITION_INDEPENDENT_CODE ON)
set_target_properties(chinese_core PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN YES
)
target_compile_definitions(chinese_core PRIVATE CHINESE_CORE_EXPORTS)

# ─── 测试 ───────────────────────────────────────────────────────────────────────

# 单元测试
enable_testing()
add_subdirectory(tests)
