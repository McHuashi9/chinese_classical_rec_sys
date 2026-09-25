// 桥层文本域（v1.4.0 工作项 3）：text_get_count / text_get_all / text_get_detail /
// text_get_annotations / text_get_translation，共 5 个导出符号。
//
// 工作项 2 下沉：annotations_raw / translation 单列读取 → TextRepository（原手写 stmt）。

#include "bridge_internal.h"

#include <algorithm>
#include <cstring>
#include <string>

extern "C" CHINESE_CORE_EXPORT int text_get_count()
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    return static_cast<int>(S().texts->size());
    });
}

extern "C" CHINESE_CORE_EXPORT void text_get_all(TextInfo* out, int max_count)
{
    bridge_guard_void(g_mtx, [&] {
    if (!S().initialized || !out) return;
    int n = std::min(max_count, static_cast<int>(S().texts->size()));
    for (int i = 0; i < n; i++) {
        const auto& t = (*S().texts)[i];
        out[i].id = t.getId();
        std::strncpy(out[i].title, t.getTitle().c_str(), 255);
        out[i].title[255] = '\0';
        std::strncpy(out[i].author, t.getAuthor().c_str(), 127);
        out[i].author[127] = '\0';
        std::strncpy(out[i].dynasty, t.getDynasty().c_str(), 63);
        out[i].dynasty[63] = '\0';
        std::strncpy(out[i].source, t.getSource().c_str(), 63);
        out[i].source[63] = '\0';
    }
    });
}

extern "C" CHINESE_CORE_EXPORT int text_get_detail(int id, TextDetail* out)
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    if (!out) return BRIDGE_ERR_GENERIC;

    auto it = S().textIndex->find(id);
    if (it == S().textIndex->end()) {
        return BRIDGE_ERR_TEXT;
    }

    const auto& text = (*S().texts)[it->second];
    out->id = text.getId();
    std::strncpy(out->title, text.getTitle().c_str(), 255);
    out->title[255] = '\0';
    std::strncpy(out->author, text.getAuthor().c_str(), 127);
    out->author[127] = '\0';
    std::strncpy(out->dynasty, text.getDynasty().c_str(), 63);
    out->dynasty[63] = '\0';
    std::strncpy(out->source, text.getSource().c_str(), 63);
    out->source[63] = '\0';
    std::strncpy(out->background, text.getBackground().c_str(), 2047);
    out->background[2047] = '\0';
    if (text.getContent().size() > 65535) {
        LOG_WARN("bridge: text_id={} 内容截断 ({} > 65535 字节)", id, text.getContent().size());
    }
    std::strncpy(out->content, text.getContent().c_str(), 65535);
    out->content[65535] = '\0';
    out->char_count = text.getCharCount();
    for (int i = 0; i < 10; i++) {
        out->difficulties[i] = text.getDifficulty(i);
    }
    return BRIDGE_OK;
    });
}

// ─── annotations ──────────────────────────────────────────────────────────────

// 单列文本回填：查库（TextRepository）→ 截断 → 写定长缓冲。
// 无该行 → BRIDGE_ERR_TEXT；NULL/空串 → 空串 + BRIDGE_OK（与原实现一致）。
static int copyTextColumn(int id, char* out, int max_len, const std::string& value,
                          const char* label)
{
    int len = value.empty() ? 0 : static_cast<int>(value.size());
    if (len >= max_len) {
        LOG_WARN("bridge: text_id={} {} 截断 ({} > {} 字节)", id, label, len, max_len - 1);
        len = max_len - 1;
    }
    if (len > 0) {
        std::strncpy(out, value.c_str(), static_cast<size_t>(len));
        out[len] = '\0';
    } else {
        out[0] = '\0';
    }
    return BRIDGE_OK;
}

extern "C" CHINESE_CORE_EXPORT int text_get_annotations(int id, char* out, int max_len)
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    if (!out || max_len <= 0) return BRIDGE_ERR_GENERIC;

    std::string raw;
    if (!S().textRepo->getAnnotationsRaw(id, raw)) return BRIDGE_ERR_TEXT;
    return copyTextColumn(id, out, max_len, raw, "annotations_raw");
    });
}

extern "C" CHINESE_CORE_EXPORT int text_get_translation(int id, char* out, int max_len)
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    if (!out || max_len <= 0) return BRIDGE_ERR_GENERIC;

    std::string raw;
    if (!S().textRepo->getTranslation(id, raw)) return BRIDGE_ERR_TEXT;
    return copyTextColumn(id, out, max_len, raw, "translation");
    });
}
