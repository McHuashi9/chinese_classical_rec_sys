import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';

/// 公告弹出模式。
enum AnnouncementMode {
  /// 每次冷启动都弹出。
  always,

  /// 仅在新版本（公告 id 变化）后弹出一次。
  onUpdate,
}

const String kAnnouncementModeKey = 'announcement_mode';
const String kAnnouncementSeenIdKey = 'announcement_seen_id';

/// 读取公告弹出模式，默认 [AnnouncementMode.always]。
AnnouncementMode loadAnnouncementMode(SharedPreferences prefs) {
  return prefs.getString(kAnnouncementModeKey) == 'on_update'
      ? AnnouncementMode.onUpdate
      : AnnouncementMode.always;
}

/// 保存公告弹出模式。
Future<void> saveAnnouncementMode(
    SharedPreferences prefs, AnnouncementMode mode) {
  return prefs.setString(
    kAnnouncementModeKey,
    mode == AnnouncementMode.onUpdate ? 'on_update' : 'always',
  );
}

/// 本地公告：以 Markdown 文本承载“作者的话 + 版本改动”。
///
/// 维护入口为 `assets/data/announcement.md`；`id` 放在 YAML front matter 中，
/// 用于“仅更新后弹出”的版本识别。
class Announcement {
  final String id;
  final String markdown;

  const Announcement({
    required this.id,
    required this.markdown,
  });
}

/// 公告 asset 路径。
const String kAnnouncementAssetPath = 'assets/data/announcement.md';

/// 从 asset 加载当前公告。
///
/// **无兜底文案**：asset 缺失、读取失败或缺 `id` 时返回 null 并记 warn。
/// 公告的唯一真相源是 [kAnnouncementAssetPath]；调用方按“没有公告”处理，
/// 避免代码里再维护一份会过期的正文（旧实现的兜底文案曾落后两个版本）。
Future<Announcement?> loadCurrentAnnouncement() async {
  try {
    final raw = await rootBundle.loadString(kAnnouncementAssetPath);
    return parseAnnouncementOrNull(raw);
  } catch (e) {
    AppLogger().warn('公告加载失败，已跳过: $kAnnouncementAssetPath ($e)');
    return null;
  }
}

/// 解析公告文本；缺 `id` 的公告视为无效并记 warn 后返回 null。
///
/// 与 [loadCurrentAnnouncement] 共用同一套“无兜底”判定，
/// 便于在不依赖 asset 的情况下用例化验证。
Announcement? parseAnnouncementOrNull(String raw) {
  final parsed = parseAnnouncement(raw);
  if (parsed.id.isEmpty) {
    AppLogger().warn('公告缺少 front matter id，已跳过: $kAnnouncementAssetPath');
    return null;
  }
  return parsed;
}

/// front matter 中的 `id:` 行（值可带单/双引号，也可裸写）。
final RegExp _frontMatterIdPattern =
    RegExp(r'''^id:[ \t]*["']?([^"'\s]+)["']?[ \t]*$''', multiLine: true);

/// 解析 `assets/data/announcement.md`：
/// 支持以 `---` 包裹的极简 YAML front matter（目前只使用 `id`），
/// 其余内容作为 Markdown 正文。
Announcement parseAnnouncement(String raw) {
  var body = raw;
  var id = '';

  if (raw.startsWith('---')) {
    final end = raw.indexOf('\n---', 3);
    if (end != -1) {
      final match = _frontMatterIdPattern.firstMatch(raw.substring(3, end));
      if (match != null) id = match.group(1)!;
      body = raw.substring(end + 4).trim();
    }
  }

  return Announcement(id: id, markdown: body);
}
