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

# Qt 6 GUI
find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

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

# 核心逻辑静态库（排除 main.cpp，避免重复编译）
file(GLOB_RECURSE LIB_SOURCES "src/*.cpp")
list(FILTER LIB_SOURCES EXCLUDE REGEX ".*main\\.cpp$")
add_library(chinese_classical_lib STATIC ${LIB_SOURCES})

# 设置 PUBLIC 包含目录，使链接此库的目标自动获得头文件路径
target_include_directories(chinese_classical_lib PUBLIC
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/third_party/spdlog-1.17.0/include
    ${CMAKE_SOURCE_DIR}/third_party/tabulate-1.5
)

# 链接 SQLite3 和 replxx（PUBLIC 使依赖传递给链接此库的目标）
target_link_libraries(chinese_classical_lib PUBLIC sqlite3_static)

# Windows 平台链接 nowide（包含 cin/cout/cerr 全局对象定义）
if(WIN32)
    target_link_libraries(chinese_classical_lib PUBLIC nowide_static)
endif()

# 复制运行时资源到构建目录
file(COPY ${CMAKE_SOURCE_DIR}/gui/fonts/ DESTINATION ${CMAKE_BINARY_DIR}/fonts/)
file(COPY ${CMAKE_SOURCE_DIR}/data/ DESTINATION ${CMAKE_BINARY_DIR}/data/)

# 主程序（GUI）
qt_add_executable(${PROJECT_NAME}
    gui/main_gui.cpp
    gui/viewmodel/AppViewModel.cpp
    gui/viewmodel/TextListModel.cpp
    gui/viewmodel/RecommendationModel.cpp
    gui/qml.qrc
)

target_include_directories(${PROJECT_NAME} PRIVATE
    ${CMAKE_SOURCE_DIR}/gui
)

target_link_libraries(${PROJECT_NAME} PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    chinese_classical_lib
)

# Windows 平台额外链接
if(WIN32)
    target_link_libraries(${PROJECT_NAME} PRIVATE shell32)
endif()

# 单元测试
enable_testing()
add_subdirectory(tests)
