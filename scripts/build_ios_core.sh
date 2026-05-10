#!/bin/bash
# iOS 交叉编译脚本: C++ 源码 → libchinese_core.a
set -euo pipefail

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
ARCH="arm64"
MIN_IOS="15.0"
OUT_DIR="build/ios"
SOURCES=$(cat scripts/core_sources.txt)

mkdir -p "$OUT_DIR"

for src in $SOURCES; do
    obj="$OUT_DIR/$(basename "$src").o"
    echo "  CC $src -> $obj"
    case "$src" in
        *.c)
            xcrun clang -c -arch "$ARCH" -isysroot "$SDK_PATH" \
                -miphoneos-version-min="$MIN_IOS" \
                -I . -I include -I third_party/sqlite3 \
                -DSQLITE_OS_UNIX=1 \
                "$src" -o "$obj"
            ;;
        *)
            xcrun clang++ -c -arch "$ARCH" -isysroot "$SDK_PATH" \
                -miphoneos-version-min="$MIN_IOS" \
                -I . -I include -I bridge -I third_party/spdlog-1.17.0/include \
                -I third_party/sqlite3 -I third_party/nowide/include \
                -std=c++17 -fvisibility=default -D__APPLE__ \
                -DSPDLOG_ACTIVE_LEVEL=SPDLOG_LEVEL_DEBUG \
                -DAPP_VERSION='"0.4.0"' \
                "$src" -o "$obj"
            ;;
    esac
done

ar rcs "$OUT_DIR/libchinese_core.a" "$OUT_DIR"/*.o
echo "→ $OUT_DIR/libchinese_core.a"
