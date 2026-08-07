/// DB 版本串比较。
///
/// 版本格式：`YYYYMMDD-hash`（旧）或 `YYYYMMDDHHMM-hash`（新，2026-08 起）。
/// 定长数字前缀 → 数值比较即可决定新旧（旧格式与定长前缀字典序兼容）；
/// 数字前缀相同时（同日同分）无法严格判新，用 hash 字典序做确定性兜底。
/// 无法解析的版本（如 'unknown'、空串）视为最旧。
///
/// 返回：a 比 b 新则 >0，相等 0，旧则 <0。
int compareDbVersions(String a, String b) {
  final pa = _parseDbVersion(a);
  final pb = _parseDbVersion(b);
  if (pa == null && pb == null) return 0;
  if (pa == null) return -1;
  if (pb == null) return 1;
  if (pa.$1 != pb.$1) return pa.$1.compareTo(pb.$1);
  if (pa.$2 == pb.$2) return 0;
  if (pa.$2 == null) return -1;
  if (pb.$2 == null) return 1;
  return pa.$2!.compareTo(pb.$2!);
}

/// 方向判断：candidate 是否比 current 新（绝不降级的唯一判据）。
bool isDbNewer(String candidate, String current) =>
    compareDbVersions(candidate, current) > 0;

/// 版本格式：`YYYYMMDD-hash`（旧）或 `YYYYMMDDHHMM-hash`（新，2026-08 起）。
/// 只接受定长 8 位或 12 位数字前缀（其余位数视为不可解析→最旧，宁可跳过也不误判）。
final _dbVersionRe = RegExp(r'^\s*(\d{8}|\d{12})(?:[-_]([0-9a-fA-F]+))?\s*$');

(int, String?)? _parseDbVersion(String v) {
  final m = _dbVersionRe.firstMatch(v);
  if (m == null) return null;
  return (int.parse(m.group(1)!), m.group(2));
}
