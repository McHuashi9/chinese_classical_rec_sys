import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/log_redaction.dart';

void main() {
  group('redactPathForLog', () {
    test('POSIX、Windows、file URI 与 UNC 路径只保留 basename', () {
      expect(redactPathForLog('/home/alice/app/classical.db'),
          '<appdata>/classical.db');
      expect(redactPathForLog(r'C:\Users\alice\AppData\classical.db'),
          '<appdata>/classical.db');
      expect(redactPathForLog('C:/Users/alice/AppData/classical.db'),
          '<appdata>/classical.db');
      expect(redactPathForLog('file:///data/user/0/app/files/user.db'),
          '<appdata>/user.db');
      expect(
          redactPathForLog(r'\\server\share\app\user.db'), '<appdata>/user.db');
      expect(redactPathForLog('classical.db'), '<appdata>/classical.db');
    });

    test('带空格路径只保留 basename', () {
      expect(redactPathForLog(r'C:\Users\alice\My Documents\user.db'),
          '<appdata>/user.db');
      expect(redactPathForLog('/home/alice/My Documents/user.db'),
          '<appdata>/user.db');
    });

    test('空路径有稳定占位', () {
      expect(redactPathForLog(''), '<path>');
    });
  });

  group('redactLogText', () {
    test('脱敏异常串中的 POSIX 与 Windows 绝对路径并保留上下文', () {
      const input = 'DB 打开失败: /home/alice/app/classical.db '
          r'和 C:\Users\alice\AppData\user.db';
      final out = redactLogText(input);

      expect(out, contains('<appdata>/classical.db'));
      expect(out, contains('<appdata>/user.db'));
      expect(out, isNot(contains('alice')));
      expect(out, isNot(contains('/home/')));
      expect(out, isNot(contains(r'C:\Users')));
    });

    test('脱敏 file URI、正斜杠盘符、UNC 与带空格路径', () {
      const input = 'paths: file:///data/user/0/app/files/user.db; '
          'C:/Users/alice/AppData/classical.db; '
          r'\\server\share\app\user.db; '
          r'C:\Users\alice\My Documents\user.db';
      final out = redactLogText(input);

      expect(out, contains('<appdata>/user.db'));
      expect(out, contains('<appdata>/classical.db'));
      expect(out, isNot(contains('alice')));
      expect(out, isNot(contains('file:///')));
      expect(out, isNot(contains('My Documents')));
      expect(out, isNot(contains(r'\\server')));
    });

    test('普通文本与 URL 不被误伤', () {
      const input = '请求 https://example.com/releases 失败，用户 id=3';
      expect(redactLogText(input), input);
    });
  });
}
