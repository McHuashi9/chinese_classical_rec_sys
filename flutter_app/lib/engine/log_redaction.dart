/// 日志脱敏：把绝对文件路径裁成 `<appdata>/<basename>`。
///
/// C++ 侧日志脱敏见 `bridge/log_redact.h`；Dart 侧统一从 AppLogger 入口调用
/// [redactLogText]，避免异常串中的 `/home/alice/...`、`C:\Users\...`、
/// `file:///...` 或 UNC 路径进入日志。
String redactPathForLog(String path) {
  if (path.isEmpty) return '<path>';
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '<path>';
  return '<appdata>/${parts.last}';
}

// 路径的目录段可含空格；basename 以非空白 token 收口，避免吞掉后续日志正文。
// 一次 regex replace 处理所有候选，避免先替换出的 `<appdata>/...` 被后续规则再次扫描。
const String _pathStopChars = r'\r\n,;)\]}>，；。';

final RegExp _pathRegex = RegExp(
  '(?:file://[^\\s$_pathStopChars]+)'
  '|(?:\\\\\\\\[^\\\\/\\r\\n,;)\\]}>，；。]+(?:\\\\[^\\\\/\\r\\n,;)\\]}>，；。]+)*'
  '\\\\[^\\\\/\\r\\n\\s,;)\\]}>，；。]+)'
  '|(?:(?<![A-Za-z0-9+.-])[A-Za-z]:[\\\\/]'
  '(?:[^\\\\/\\r\\n,;)\\]}>，；。]*[\\\\/])*'
  '[^\\\\/\\r\\n\\s,;)\\]}>，；。]+)'
  '|(?:(?<![\\w:/])/(?:[^/\\r\\n,;)\\]}>，；。]*/)*'
  '[^/\\r\\n\\s,;)\\]}>，；。]+)',
);

/// 对任意日志文本做路径脱敏，保持其余文本不变。
String redactLogText(String text) {
  return text.replaceAllMapped(
    _pathRegex,
    (match) => redactPathForLog(match.group(0)!),
  );
}
