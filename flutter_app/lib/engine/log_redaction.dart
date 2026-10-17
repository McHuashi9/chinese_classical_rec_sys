/// 日志脱敏：把绝对文件路径裁成 `<appdata>/<basename>`。
///
/// C++ 侧日志脱敏见 `bridge/log_redact.h`；Dart 侧统一从 AppLogger 入口调用
/// [redactLogText]，避免异常串中的 `/home/alice/...` 或 `C:\Users\...` 进入日志。
String redactPathForLog(String path) {
  if (path.isEmpty) return '<path>';
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '<path>';
  return '<appdata>/${parts.last}';
}

final RegExp _windowsAbsolutePath = RegExp(r'[A-Za-z]:\\[^\s]+');
final RegExp _posixAbsolutePath = RegExp(r'(?<![\w:/])/(?:[^/\s]+/)*[^/\s]+');

/// 对任意日志文本做路径脱敏，保持其余文本不变。
String redactLogText(String text) {
  var redacted = text.replaceAllMapped(
    _windowsAbsolutePath,
    (match) => redactPathForLog(match.group(0)!),
  );
  redacted = redacted.replaceAllMapped(
    _posixAbsolutePath,
    (match) => redactPathForLog(match.group(0)!),
  );
  return redacted;
}
