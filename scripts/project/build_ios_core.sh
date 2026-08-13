#!/bin/bash
# iOS 交叉编译脚本: C++ 源码 → libchinese_core.a
set -euo pipefail

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
ARCH="arm64"
MIN_IOS="15.0"
OUT_DIR="build/ios"
# 动态生成源码列表（与 CMakeLists.txt 过滤器同步）
SOURCES=$(find src -name '*.cpp' \
  ! -name 'main.cpp' \
  ! -name 'CommandRegistry.cpp' \
  ! -name 'CommandParser.cpp' \
  ! -name 'ExitCommand.cpp' \
  ! -name 'HelpCommand.cpp' \
  ! -name 'LibraryCommand.cpp' \
  ! -name 'LogCommand.cpp' \
  ! -name 'ReadCommand.cpp' \
  ! -name 'RecommendCommand.cpp' \
  ! -name 'PathUtils.cpp')
SOURCES="$SOURCES bridge/bridge.cpp"

# 从 pubspec.yaml 读取版本号
APP_VERSION=$(sed -n 's/^version: //p' flutter_app/pubspec.yaml)

mkdir -p "$OUT_DIR"

for src in $SOURCES; do
    obj="$OUT_DIR/$(basename "$src").o"
    echo "  CC $src -> $obj"
    case "$src" in
        *.c)
            xcrun clang -c -Wall -Wextra -Werror -arch "$ARCH" -isysroot "$SDK_PATH" \
                -miphoneos-version-min="$MIN_IOS" \
                -I . -I include -I third_party/sqlite3 \
                -DSQLITE_OS_UNIX=1 \
                "$src" -o "$obj"
            ;;
        *)
            xcrun clang++ -c -Wall -Wextra -Werror -arch "$ARCH" -isysroot "$SDK_PATH" \
                -miphoneos-version-min="$MIN_IOS" \
                -I . -I include -I bridge -I third_party/spdlog-1.17.0/include \
                -I third_party/sqlite3 -I third_party/nowide/include \
                -std=c++17 -fvisibility=default -D__APPLE__ \
                -DSPDLOG_ACTIVE_LEVEL=SPDLOG_LEVEL_DEBUG \
                -DAPP_VERSION=\"$APP_VERSION\" \
                "$src" -o "$obj"
            ;;
    esac
done

ar rcs "$OUT_DIR/libchinese_core.a" "$OUT_DIR"/*.o
echo "→ $OUT_DIR/libchinese_core.a"
