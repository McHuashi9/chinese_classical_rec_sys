# 单元测试构建配置

# 包含 Catch2 头文件
include_directories(${CMAKE_SOURCE_DIR}/third_party/catch2)

# 测试源文件
set(TEST_SOURCES
    test_main.cpp
    test_math_functions.cpp
    test_table_formatter.cpp
)

# Catch2 编译源
set(CATCH2_SOURCES
    ${CMAKE_SOURCE_DIR}/third_party/catch2/catch_amalgamated.cpp
)

# 创建测试可执行文件
add_executable(run_tests
    ${TEST_SOURCES}
    ${CATCH2_SOURCES}
)

# 链接核心逻辑静态库
target_link_libraries(run_tests PRIVATE chinese_classical_lib)

# Windows 平台额外链接
if(WIN32)
    target_link_libraries(run_tests PRIVATE shell32)
endif()

# 添加到 CTest（暂时绕过 Windows 平台路径问题）
if(NOT WIN32)
    add_test(NAME MathFunctionsTests COMMAND run_tests)
endif()
