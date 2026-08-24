import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 反馈邮件收件人。
const String kFeedbackRecipient = 'mc_huashi9@163.com';

/// 反馈草稿：包含用户填写内容与自动收集的诊断信息。
///
/// 当前用于生成 `mailto:` 草稿；后续接 Cloudflare Worker 时，
/// 同一份数据可以改由 telemetry POST builder 复用。
class FeedbackDraft {
  const FeedbackDraft({
    required this.type,
    required this.title,
    required this.description,
    required this.diagnostics,
    this.appVersion,
    this.platform,
    this.contentDataVersion,
    this.schemaVersions,
    this.logTail,
    this.screenshotPath,
  });

  /// 反馈类型，例如 `Bug` / `建议`。
  final String type;

  /// 反馈标题。
  final String title;

  /// 用户填写的详细描述。
  final String description;

  /// 自动收集的诊断信息文本。
  final String diagnostics;

  /// 结构化诊断字段，供 Worker 在线提交复用。
  final String? appVersion;
  final String? platform;
  final String? contentDataVersion;
  final String? schemaVersions;
  final String? logTail;

  /// 随反馈附带的本地截图完整路径（仅用于邮件/复制正文，不上传）。
  final String? screenshotPath;

  String get subject {
    final label = type == 'Bug' ? 'Bug反馈' : '建议';
    return '【$label】$title';
  }

  String get body => '$diagnostics\n\n【问题描述】\n$description';
}

/// 生成 `mailto:` URI。
///
/// 必须使用 [Uri.encodeComponent] 编码主题和正文，避免中文、换行、
/// `&`、`?`、`%`、`#` 等字符破坏 URI。
String buildMailtoUri({
  required String recipient,
  required String subject,
  required String body,
}) {
  return 'mailto:$recipient?subject=${Uri.encodeComponent(subject)}'
      '&body=${Uri.encodeComponent(body)}';
}

/// 组装“收件人 + 主题 + 正文”的完整纯文本，方便用户复制到任意邮箱。
String buildFullFeedbackText({
  required String recipient,
  required FeedbackDraft draft,
}) {
  final screenshot =
      draft.screenshotPath == null ? '' : '\n\n截图：${draft.screenshotPath}';
  return '收件人：$recipient\n主题：${draft.subject}\n\n${draft.body}$screenshot';
}

/// 组装环境信息 + 日志尾部。
String buildDiagnosticText({
  required String appVersion,
  required String platform,
  required String contentDataVersion,
  required String schemaVersions,
  required String logTail,
}) {
  return '【环境信息】\n'
      'App 版本：$appVersion\n'
      '平台：$platform\n'
      '内容数据版本：$contentDataVersion\n'
      '数据库格式：$schemaVersions\n'
      '\n'
      '【日志尾部】\n'
      '$logTail';
}

/// 读取应用支持目录下 `logs/app.log` 的尾部。
///
/// [logDirectory] 可注入，便于测试；为空时使用 [getApplicationSupportDirectory]。
/// 默认最多 [maxLines] 行；若文本超过 [maxChars] 字符，保留末尾部分。
Future<String> readLogTail({
  String? logDirectory,
  int maxLines = 100,
  int maxChars = 8 * 1024,
}) async {
  try {
    final dirPath =
        logDirectory ?? (await getApplicationSupportDirectory()).path;
    final file = File('$dirPath/logs/app.log');
    if (!await file.exists()) return '（暂无日志文件）';
    final lines = await file.readAsLines();
    final tail = lines.length > maxLines
        ? lines.sublist(lines.length - maxLines)
        : lines;
    var text = tail.join('\n');
    if (text.length > maxChars) {
      text = text.substring(text.length - maxChars);
    }
    return text;
  } catch (e) {
    return '（读取日志失败：$e）';
  }
}
