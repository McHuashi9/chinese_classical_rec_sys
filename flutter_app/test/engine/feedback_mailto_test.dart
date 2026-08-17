import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/feedback_mailto.dart';

void main() {
  group('buildMailtoUri', () {
    test('中文与换行被正确编码', () {
      final uri = buildMailtoUri(
        recipient: 'a@example.com',
        subject: '【Bug反馈】v1.0.2 中文标题',
        body: '第一行\n第二行',
      );

      expect(uri, startsWith('mailto:a@example.com?subject='));
      expect(uri, isNot(contains('\n')));
      expect(uri, contains('%0A'));
      expect(uri, contains('%E3%80%90'));
    });

    test('特殊字符 & ? % # 不被破坏', () {
      final uri = buildMailtoUri(
        recipient: 'a@example.com',
        subject: 'a&b?c%d#e',
        body: 'x=1&y=2?z=3%4#5',
      );

      expect(uri, contains('subject=a%26b%3Fc%25d%23e'));
      expect(uri, contains('body=x%3D1%26y%3D2%3Fz%3D3%254%235'));
      // 原始特殊字符不应直接出现在查询参数里
      expect(uri, isNot(contains('subject=a&b')));
      expect(uri, isNot(contains('body=x=1&y=2')));
    });
  });

  group('FeedbackDraft', () {
    test('subject 和 body 按类型与诊断信息组装', () {
      const draft = FeedbackDraft(
        type: 'Bug',
        title: '初始化后无法进入阅读',
        description: '点击文章后一直转圈',
        diagnostics: '【环境信息】\nApp 版本：1.0.2',
      );

      expect(draft.subject, '【Bug反馈】初始化后无法进入阅读');
      expect(
        draft.body,
        '【环境信息】\nApp 版本：1.0.2\n\n【问题描述】\n点击文章后一直转圈',
      );
    });

    test('建议类型使用“建议”前缀', () {
      const draft = FeedbackDraft(
        type: '建议',
        title: '希望增加夜间模式',
        description: '描述',
        diagnostics: '诊断',
      );

      expect(draft.subject, '【建议】希望增加夜间模式');
    });
  });

  group('buildFullFeedbackText', () {
    test('包含收件人、主题、正文', () {
      const draft = FeedbackDraft(
        type: 'Bug',
        title: '标题',
        description: '描述',
        diagnostics: '诊断',
      );
      final text = buildFullFeedbackText(
        recipient: 'mc_huashi9@163.com',
        draft: draft,
      );

      expect(text, contains('收件人：mc_huashi9@163.com'));
      expect(text, contains('主题：【Bug反馈】标题'));
      expect(text, contains('诊断'));
      expect(text, contains('描述'));
    });
  });

  group('buildDiagnosticText', () {
    test('包含环境信息与日志尾部', () {
      final text = buildDiagnosticText(
        appVersion: '1.0.2',
        platform: 'Windows',
        contentDataVersion: 'data-20260816-213645',
        schemaVersions: '用户 1 · 内容 1',
        logTail: 'line1\nline2',
      );

      expect(text, contains('App 版本：1.0.2'));
      expect(text, contains('平台：Windows'));
      expect(text, contains('内容数据版本：data-20260816-213645'));
      expect(text, contains('数据库格式：用户 1 · 内容 1'));
      expect(text, contains('line1\nline2'));
    });
  });

  group('readLogTail', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('feedback_log_test');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('日志不存在时返回提示', () async {
      final result = await readLogTail(logDirectory: tempDir.path);
      expect(result, '（暂无日志文件）');
    });

    test('读取最后 maxLines 行', () async {
      final logDir = Directory('${tempDir.path}/logs')..createSync(recursive: true);
      final file = File('${logDir.path}/app.log');
      file.writeAsStringSync(List.generate(120, (i) => 'line$i').join('\n'));

      final result = await readLogTail(
        logDirectory: tempDir.path,
        maxLines: 100,
      );

      expect(result, startsWith('line20'));
      expect(result, isNot(contains('line0\n')));
      expect(result.split('\n').length, 100);
    });

    test('超过 maxChars 时保留末尾', () async {
      final logDir = Directory('${tempDir.path}/logs')..createSync(recursive: true);
      final file = File('${logDir.path}/app.log');
      file.writeAsStringSync('a' * 2000);

      final result = await readLogTail(
        logDirectory: tempDir.path,
        maxLines: 100,
        maxChars: 100,
      );

      expect(result.length, 100);
      expect(result, 'a' * 100);
    });

    test('读取失败时返回错误提示', () async {
      // 写入非法 UTF-8，readAsLines 解码失败会抛错，从而走失败分支。
      final logDir = Directory('${tempDir.path}/logs')..createSync(recursive: true);
      File('${logDir.path}/app.log').writeAsBytesSync([0xFF, 0xFE, 0x00]);

      final result = await readLogTail(logDirectory: tempDir.path);
      expect(result, contains('（读取日志失败'));
    });
  });
}
