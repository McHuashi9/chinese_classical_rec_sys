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

/// v1.0.0 首版公告。后续版本若需再次弹公告，更换 id 并更新文案即可。
const Announcement kCurrentAnnouncement = Announcement(
  id: 'v1.0.0-1',
  authorMessage: '感谢使用文言文推荐系统。\n\n'
      '这个版本开始采用“内容库 + 用户库”双库结构：内容更新不会再影响你的学习进度。'
      '首次使用需要完成 6 道简短初始化题，帮助我们更准确地为你推荐合适的篇目。',
  changes: '· 内容库与用户库分离，数据更新更安全\n'
      '· 新增新用户初始化引导\n'
      '· 设置页可查看数据版本与存储状态\n'
      '· 新增虚词 / 断句题型\n'
      '· 修复若干已知问题',
);
