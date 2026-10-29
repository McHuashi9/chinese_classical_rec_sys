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

/// 轮转文件探测上限（spdlog 保留 3 个历史文件，留出余量）。
const int kMaxRotatedLogFiles = 5;

/// [readLogTail] 在没有可用本地日志文件时返回的占位文本（A6）。
const String kEmptyLogTailPlaceholder = '（暂无日志文件）';

/// 移动端日志同时写入应用日志文件与系统日志；文件尚未生成时的反馈说明。
///
/// 设置页日志卡与反馈弹窗共用同一句，避免两处口径漂移。
const String kMobileSystemLogNotice =
    '本平台日志同时写入应用日志文件与系统日志（Android logcat / iOS 控制台）；'
    '日志文件尚未生成时，反馈可附操作步骤或截图';

/// 平台名是否属于移动端（日志同时写文件与系统日志）。
bool isMobileLogPlatform(String platformName) {
  final name = platformName.toLowerCase();
  return name.contains('android') || name.contains('ios');
}

/// 日志尾部是否为空（没有本地日志文件、读取为空或命中空占位）。
bool isEmptyLogTail(String? logTail) =>
    logTail == null ||
    logTail.trim().isEmpty ||
    logTail == kEmptyLogTailPlaceholder;

/// 移动端日志为空时，把空占位换成平台事实说明；其余情况原样返回。
///
/// 只改写“占位”，不会把真实日志内容替换掉；桌面端（本地有文件）也不改写。
String logTailForFeedback(String logTail, {required String platformName}) =>
    isMobileLogPlatform(platformName) && isEmptyLogTail(logTail)
        ? kMobileSystemLogNotice
        : logTail;

/// 读取应用支持目录下 `logs/` 的日志尾部。
///
/// [logDirectory] 可注入，便于测试；为空时使用 [getApplicationSupportDirectory]。
/// A6：除 `app.log` 外，按“旧 → 新”依次拼上 `app.2.log`、`app.1.log`
/// 等轮转文件，再统一截尾——否则“上次会话（含崩溃前最后一段）”会被
/// 轮转掉而取不到。默认最多 [maxLines] 行；若文本超过 [maxChars] 字符，
/// 保留末尾部分。
Future<String> readLogTail({
  String? logDirectory,
  int maxLines = 100,
  int maxChars = 8 * 1024,
}) async {
  try {
    final dirPath =
        logDirectory ?? (await getApplicationSupportDirectory()).path;
    final files = <File>[
      for (var i = kMaxRotatedLogFiles; i >= 1; i--)
        File('$dirPath/logs/app.$i.log'),
      File('$dirPath/logs/app.log'),
    ];
    final lines = <String>[];
    for (final file in files) {
      if (!await file.exists()) continue;
      lines.addAll(await file.readAsLines());
    }
    if (lines.isEmpty) return kEmptyLogTailPlaceholder;
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
