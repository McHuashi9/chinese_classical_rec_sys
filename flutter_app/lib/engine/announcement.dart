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

/// 本地公告模板：作者的话 + 版本改动。
/// 发版时更新 [Announcement.id] 与文案；设置页「公告 / 作者的话」回看同一份数据。
class Announcement {
  final String id;
  final String authorMessage;
  final String changes;

  const Announcement({
    required this.id,
    required this.authorMessage,
    required this.changes,
  });
}

/// v1.1.1 维护版公告。
const Announcement kCurrentAnnouncement = Announcement(
  id: 'v1.1.1-1',
  authorMessage: '感谢使用文言文推荐系统。\n\n'
      '这个版本是维护版，重点修复了初始化流程、数据库错误提示等体验问题，'
      '并新增了七夕小彩蛋与学习数据导出，方便你把学习数据交给开发者做后续参数校准。',
  changes: '· 修复损坏用户库误报版本不兼容\n'
      '· 初始化阅读页与正常阅读页保持一致\n'
      '· 新建未初始化档案后强制进入初始化流程\n'
      '· 答题结果页展示全部选项与正误标记\n'
      '· 随堂练习仅对已读文章展示\n'
      '· 设置页可打开日志所在位置\n'
      '· 新增七夕节日卡片\n'
      '· 公告默认每次启动弹出，可改为仅更新后弹出\n'
      '· 设置页可导出学习数据\n'
      '· 阅读效应阈值按文章动态计算',
);
