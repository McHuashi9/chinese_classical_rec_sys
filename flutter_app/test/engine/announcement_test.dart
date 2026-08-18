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
}
