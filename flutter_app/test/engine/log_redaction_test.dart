import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/log_redaction.dart';

void main() {
  group('redactPathForLog', () {
    test('POSIX 与 Windows 路径只保留 basename', () {
      expect(redactPathForLog('/home/alice/app/classical.db'),
          '<appdata>/classical.db');
      expect(redactPathForLog(r'C:\Users\alice\AppData\classical.db'),
          '<appdata>/classical.db');
      expect(redactPathForLog('classical.db'), '<appdata>/classical.db');
    });

    test('空路径有稳定占位', () {
      expect(redactPathForLog(''), '<path>');
    });
  });

  group('redactLogText', () {
    test('脱敏异常串中的绝对路径并保留上下文', () {
      const input = 'DB 打开失败: /home/alice/app/classical.db '
          r'和 C:\Users\alice\AppData\user.db';
      final out = redactLogText(input);

      expect(out, contains('<appdata>/classical.db'));
      expect(out, contains('<appdata>/user.db'));
      expect(out, isNot(contains('alice')));
      expect(out, isNot(contains('/home/')));
      expect(out, isNot(contains(r'C:\Users')));
    });

    test('普通文本与 URL 不被误伤', () {
      const input = '请求 https://example.com/releases 失败，用户 id=3';
      expect(redactLogText(input), input);
    });
  });
}
