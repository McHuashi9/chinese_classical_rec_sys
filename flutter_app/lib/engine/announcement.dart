import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

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

/// asset 缺失/解析失败时的兜底公告。
const Announcement kFallbackAnnouncement = Announcement(
  id: 'v1.2.1-1',
  markdown: '感谢使用文言文推荐系统。\n\n'
      '这个版本是维护版，重点完善了初始化答题引导、节日弹窗与设置页日志目录体验。\n\n'
      '## 版本改动\n\n'
      '- 初始化答题页新增“回看原文”引导\n'
      '- 七夕节日入口改为冷启动弹窗\n'
      '- 设置页日志按钮改为打开日志目录',
);

/// 从 asset 加载当前公告；失败时返回 [kFallbackAnnouncement]。
Future<Announcement> loadCurrentAnnouncement() async {
  try {
    final raw = await rootBundle.loadString(kAnnouncementAssetPath);
    final parsed = parseAnnouncement(raw);
    return parsed.id.isEmpty ? kFallbackAnnouncement : parsed;
  } catch (_) {
    return kFallbackAnnouncement;
  }
}

/// 解析 `assets/data/announcement.md`：
/// 支持以 `---` 包裹的极简 YAML front matter（目前只使用 `id`），
/// 其余内容作为 Markdown 正文。
Announcement parseAnnouncement(String raw) {
  var body = raw;
  var id = '';

  if (raw.startsWith('---')) {
    final end = raw.indexOf('\n---', 3);
    if (end != -1) {
      final frontMatter = raw.substring(3, end).trim();
      for (final line in frontMatter.split('\n')) {
        final colon = line.indexOf(':');
        if (colon <= 0) continue;
        final key = line.substring(0, colon).trim();
        if (key == 'id') {
          id = line
              .substring(colon + 1)
              .trim()
              .replaceAll('"', '')
              .replaceAll("'", '');
        }
      }
      body = raw.substring(end + 4).trim();
    }
  }

  return Announcement(id: id, markdown: body);
}
