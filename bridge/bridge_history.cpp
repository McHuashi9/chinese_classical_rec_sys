// 桥层历史域（v1.4.0 工作项 3）：history_add_record / history_get_recent /
// history_get_total_count / history_get_tracked_text_ids，共 4 个导出符号。

#include "bridge_internal.h"

#include <algorithm>
#include <cstdint>

extern "C" CHINESE_CORE_EXPORT int history_add_record(int text_id, double read_time, int64_t timestamp)
{
    return bridge_guard(g_mtx, [&]() -> int {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    bool ok = S().historyRepo->addRecord(S().activeUserId, text_id, read_time,
                                         static_cast<time_t>(timestamp));
    if (ok) {
        LOG_INFO("bridge: history_add_record text_id={} read_time={:.1f}s", text_id, read_time);
    }
    return ok ? BRIDGE_OK : BRIDGE_ERR_GENERIC;
    });
}

extern "C" CHINESE_CORE_EXPORT int history_get_recent(int limit, ReadingRecordData* out, int max_count)
{
    return bridge_guard(g_mtx, [&]() -> int {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    if (!out || limit <= 0 || max_count <= 0) return BRIDGE_ERR_GENERIC;

    std::vector<ReadingRecord> records;
    if (!S().historyRepo->getRecentRecords(S().activeUserId, limit, records)) {
        return BRIDGE_ERR_GENERIC;
    }
    int n = std::min(static_cast<int>(records.size()), max_count);

    for (int i = 0; i < n; i++) {
        out[i].id = records[i].id;
        out[i].text_id = records[i].textId;
        out[i].read_time = records[i].readTime;
        out[i].timestamp = static_cast<int64_t>(records[i].timestamp);
    }
    return n;
    });
}

extern "C" CHINESE_CORE_EXPORT int history_get_total_count()
{
    return bridge_guard(g_mtx, [&]() -> int {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    int total = 0;
    if (!S().historyRepo->getTotalReadCount(S().activeUserId, total)) {
        return BRIDGE_ERR_GENERIC;
    }
    return total;
    });
}

extern "C" CHINESE_CORE_EXPORT int history_get_tracked_text_ids(int* out, int max_count)
{
    return bridge_guard(g_mtx, [&]() -> int {
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    if (!out || max_count <= 0) return BRIDGE_ERR_GENERIC;

    std::vector<int> ids;
    if (!S().historyRepo->getTrackedTextIds(S().activeUserId, ids)) {
        return BRIDGE_ERR_GENERIC;
    }
    int n = std::min(static_cast<int>(ids.size()), max_count);

    for (int i = 0; i < n; i++) {
        out[i] = ids[i];
    }
    return n;
    });
}
