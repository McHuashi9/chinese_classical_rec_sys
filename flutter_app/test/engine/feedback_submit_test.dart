import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:chinese_classical_rec_sys/engine/feedback_mailto.dart';
import 'package:chinese_classical_rec_sys/engine/feedback_submit.dart';

void main() {
  const draft = FeedbackDraft(
    type: 'Bug',
    title: '标题',
    description: '描述',
    diagnostics: '诊断',
    appVersion: '1.1.0',
    platform: 'Linux',
    contentDataVersion: 'data-1',
    schemaVersions: '用户 1 · 内容 1',
    logTail: 'line1',
  );

  group('buildFeedbackPayload', () {
    test('包含结构化字段', () {
      final payload = buildFeedbackPayload(draft);

      expect(payload['type'], 'Bug');
      expect(payload['title'], '标题');
      expect(payload['description'], '描述');
      expect(payload['appVersion'], '1.1.0');
      expect(payload['platform'], 'Linux');
      expect(payload['contentDataVersion'], 'data-1');
      expect(payload['schemaVersions'], '用户 1 · 内容 1');
      expect(payload['logTail'], 'line1');
      expect(payload['clientTs'], isA<String>());
    });
  });

  group('submitFeedbackToWorker', () {
    test('成功时返回 ok 和 id', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(),
            'https://example.workers.dev/api/feedback');
        expect(request.headers['Content-Type'], 'application/json');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['title'], '标题');
        return http.Response(
          jsonEncode({'ok': true, 'id': 'feedback/2026-08/x.json'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final result = await submitFeedbackToWorker(
        draft: draft,
        baseUrl: 'https://example.workers.dev',
        client: client,
      );

      expect(result.ok, true);
      expect(result.id, 'feedback/2026-08/x.json');
    });

    test('服务端返回错误时保留错误信息', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'ok': false, 'error': 'title 不能为空'}),
          400,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final result = await submitFeedbackToWorker(
        draft: draft,
        baseUrl: 'https://example.workers.dev',
        client: client,
      );

      expect(result.ok, false);
      expect(result.error, 'title 不能为空');
    });

    test('网络异常时返回友好错误', () async {
      final client = MockClient((request) async {
        throw Exception('connection refused');
      });

      final result = await submitFeedbackToWorker(
        draft: draft,
        baseUrl: 'https://example.workers.dev',
        client: client,
      );

      expect(result.ok, false);
      expect(result.error, contains('无法连接开发者服务'));
    });
  });
}
