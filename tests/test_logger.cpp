#include <catch_amalgamated.hpp>

#include "log_redact.h"
#include "utils/Logger.h"

#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>

namespace {

struct TempLoggerDir {
    explicit TempLoggerDir(const std::string& tag)
    {
        path = std::filesystem::temp_directory_path() /
               ("chinese_core_logger_" + tag + "_" +
                std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
        std::filesystem::create_directories(path);
    }

    ~TempLoggerDir()
    {
        std::error_code ec;
        std::filesystem::remove_all(path, ec);
    }

    std::string filePath() const
    {
        return (path / "app.log").string();
    }

    std::filesystem::path path;
};

std::string readFile(const std::filesystem::path& path)
{
    std::ifstream in(path, std::ios::binary);
    if (!in) return {};
    std::ostringstream out;
    out << in.rdbuf();
    return out.str();
}

}  // namespace

TEST_CASE("Logger init 同目录幂等且日志写入同一文件", "[logger]")
{
    Logger::getInstance().resetForTest();
    TempLoggerDir dir("same");

    REQUIRE(Logger::getInstance().init(dir.path.string()));
    LOG_WARN("logger same dir first");
    REQUIRE(Logger::getInstance().init(dir.path.string()));
    LOG_WARN("logger same dir second");

    const auto content = readFile(dir.filePath());
    CHECK(content.find("logger same dir first") != std::string::npos);
    CHECK(content.find("logger same dir second") != std::string::npos);
    Logger::getInstance().resetForTest();
}

TEST_CASE("Logger init 异目录重建 sink", "[logger]")
{
    Logger::getInstance().resetForTest();
    TempLoggerDir first("first");
    TempLoggerDir second("second");

    REQUIRE(Logger::getInstance().init(first.path.string()));
    LOG_WARN("logger first dir");
    REQUIRE(Logger::getInstance().init(second.path.string()));
    LOG_WARN("logger second dir");

    const auto firstContent = readFile(first.filePath());
    const auto secondContent = readFile(second.filePath());
    CHECK(firstContent.find("logger first dir") != std::string::npos);
    CHECK(firstContent.find("logger second dir") == std::string::npos);
    CHECK(secondContent.find("logger second dir") != std::string::npos);
    Logger::getInstance().resetForTest();
}

TEST_CASE("Logger 异目录重建失败时保留旧 sink 并可恢复", "[logger]")
{
    Logger::getInstance().resetForTest();
    TempLoggerDir valid("valid");
    TempLoggerDir blocker("blocker");
    const auto blockerFile = blocker.path / "not_a_dir";
    {
        std::ofstream out(blockerFile);
        out << "block";
    }

    REQUIRE(Logger::getInstance().init(valid.path.string()));
    CHECK_FALSE(Logger::getInstance().init((blockerFile / "logs").string()));
    LOG_WARN("logger after failed reinit");
    CHECK(readFile(valid.filePath()).find("logger after failed reinit") !=
          std::string::npos);

    TempLoggerDir recovered("recovered");
    REQUIRE(Logger::getInstance().init(recovered.path.string()));
    LOG_WARN("logger recovered");
    CHECK(readFile(recovered.filePath()).find("logger recovered") !=
          std::string::npos);
    Logger::getInstance().resetForTest();
}

TEST_CASE("Logger 初始化失败后可在有效目录恢复", "[logger]")
{
    Logger::getInstance().resetForTest();
    TempLoggerDir blocker("blocker_first");
    const auto blockerFile = blocker.path / "not_a_dir";
    {
        std::ofstream out(blockerFile);
        out << "block";
    }
    CHECK_FALSE(Logger::getInstance().init((blockerFile / "logs").string()));

    TempLoggerDir valid("valid_after_failure");
    REQUIRE(Logger::getInstance().init(valid.path.string()));
    LOG_WARN("logger after first failure");
    CHECK(readFile(valid.filePath()).find("logger after first failure") !=
          std::string::npos);
    Logger::getInstance().resetForTest();
}

TEST_CASE("Logger 文件达到轮转阈值后生成 app.1.log", "[logger]")
{
    Logger::getInstance().resetForTest();
    TempLoggerDir dir("rotate");
    REQUIRE(Logger::getInstance().init(dir.path.string()));

    const std::string payload(200, 'x');
    for (int i = 0; i < 700; ++i) {
        LOG_WARN("rotate {} {}", i, payload);
    }

    CHECK(std::filesystem::exists(dir.path / "app.1.log"));
    CHECK(std::filesystem::exists(dir.path / "app.log"));
    Logger::getInstance().resetForTest();
}

TEST_CASE("日志路径脱敏只保留 basename", "[logger][redact]")
{
    CHECK(bridge_log::redactPath("/home/alice/app/classical.db") ==
          "<appdata>/classical.db");
    CHECK(bridge_log::redactPath("C:\\Users\\alice\\AppData\\user.db") ==
          "<appdata>/user.db");
    CHECK(bridge_log::redactPath("") == "<path>");
}
