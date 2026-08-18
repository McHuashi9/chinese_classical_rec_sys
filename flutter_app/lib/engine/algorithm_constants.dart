// 算法参数 — 必须同步 include/core/Config.h
// Config.h:12-13 为规范来源
const double deltaStar = 0.13;
const double sigma = 0.25;

/// 阅读效应阈值：按文章最低推荐阅读时间动态计算。
/// `T_min = charCount / v_max * 60`；无字数时兜底 30s。
/// 必须同步 include/core/Config.h 的 MAX_READ_SPEED / MIN_READ_TIME。
const double maxReadSpeed = 150.0;
const double fallbackMinReadTime = 30.0;

double minReadTimeSeconds(int charCount) {
  if (charCount <= 0) return fallbackMinReadTime;
  return charCount / maxReadSpeed * 60.0;
}
