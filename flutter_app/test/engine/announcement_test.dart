import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/engine/announcement.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('公告弹出模式持久化', () {
    test('默认 always', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(loadAnnouncementMode(prefs), AnnouncementMode.always);
    });

    test('保存 onUpdate 后读取为 onUpdate', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await saveAnnouncementMode(prefs, AnnouncementMode.onUpdate);
      expect(loadAnnouncementMode(prefs), AnnouncementMode.onUpdate);
    });

    test('保存 always 后读取为 always', () async {
      SharedPreferences.setMockInitialValues({
        kAnnouncementModeKey: 'on_update',
      });
      final prefs = await SharedPreferences.getInstance();
      await saveAnnouncementMode(prefs, AnnouncementMode.always);
      expect(loadAnnouncementMode(prefs), AnnouncementMode.always);
    });
  });

  group('公告 Markdown 解析', () {
    test('解析 front matter id 与正文', () {
      const raw = '''
---
id: v1.2.1-1
---

感谢使用。

## 版本改动

- 新增功能
''';
      final announcement = parseAnnouncement(raw);
      expect(announcement.id, 'v1.2.1-1');
      expect(announcement.markdown, contains('感谢使用'));
      expect(announcement.markdown, contains('## 版本改动'));
      expect(announcement.markdown, contains('- 新增功能'));
    });

    test('没有 front matter 时 id 为空、正文原样保留', () {
      const raw = '感谢使用。\n\n## 版本改动\n\n- 新增功能';
      final announcement = parseAnnouncement(raw);
      expect(announcement.id, isEmpty);
      expect(announcement.markdown, raw.trim());
    });

    test('loadCurrentAnnouncement 能从 asset 加载公告', () async {
      final announcement = await loadCurrentAnnouncement();
      expect(announcement.id, isNotEmpty);
      expect(announcement.markdown, contains('版本改动'));
    });
  });
}
