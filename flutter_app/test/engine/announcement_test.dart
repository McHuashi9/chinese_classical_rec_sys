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

    test('id 值带引号或多余空白时仍能取出', () {
      const raw = '''
---
id:   "v9.9.9-1"
---

正文
''';
      expect(parseAnnouncement(raw).id, 'v9.9.9-1');
    });

    test('解析结果不再夹带 front matter 分隔符与 id 行', () {
      const raw = '''
---
id: v1.2.1-1
---

正文
''';
      final markdown = parseAnnouncement(raw).markdown;
      expect(markdown, '正文');
      expect(markdown, isNot(contains('---')));
      expect(markdown, isNot(contains('id:')));
    });
  });

  group('公告加载契约（无兜底真相源）', () {
    test('缺 id 的公告判为无效并返回 null', () {
      expect(parseAnnouncementOrNull('感谢使用。\n\n## 版本改动'), isNull);
    });

    test('front matter 存在但缺 id 时同样返回 null', () {
      const raw = '''
---
title: 没有 id
---

正文
''';
      expect(parseAnnouncementOrNull(raw), isNull);
    });

    test('带 id 的公告正常返回', () {
      const raw = '''
---
id: v1.3.0-1
---

正文
''';
      final announcement = parseAnnouncementOrNull(raw);
      expect(announcement, isNotNull);
      expect(announcement!.id, 'v1.3.0-1');
    });

    test('loadCurrentAnnouncement 从真实 asset 加载（断言取 asset 独有内容）', () async {
      final announcement = await loadCurrentAnnouncement();
      expect(announcement, isNotNull, reason: '内置公告 asset 不应加载失败');
      // id 必须来自 asset 的 front matter，而不是代码里的兜底常量
      expect(announcement!.id, matches(RegExp(r'^v\d+\.\d+\.\d+')));
      expect(announcement.markdown, contains('## 版本改动'));
      expect(announcement.markdown, contains('感谢您使用文言文推荐系统'),
          reason: '应为 asset 正文；旧兜底文案写的是“感谢使用文言文推荐系统”');
      expect(announcement.markdown, isNot(contains('id:')),
          reason: 'front matter 不应进入正文');
    });
  });
}
