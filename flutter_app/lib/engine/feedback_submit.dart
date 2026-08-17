import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'feedback_mailto.dart';

/// 反馈在线提交配置。
///
/// 默认指向本地 Worker，便于开发；正式发布时通过
/// `--dart-define=FEEDBACK_WORKER_URL=https://...` 注入正式地址。
class FeedbackConfig {
  static const String workerBaseUrl = String.fromEnvironment(
    'FEEDBACK_WORKER_URL',
    defaultValue: 'http://127.0.0.1:8787',
  );
}

class FeedbackSubmitResult {
  const FeedbackSubmitResult({
    required this.ok,
    this.id,
    this.error,
  });

  final bool ok;
  final String? id;
  final String? error;
}

/// 把 [FeedbackDraft] 组装成 Worker 期望的 JSON payload。
Map<String, dynamic> buildFeedbackPayload(FeedbackDraft draft) {
  return {
    'type': draft.type,
    'title': draft.title,
    'description': draft.description,
    'appVersion': draft.appVersion,
    'platform': draft.platform,
    'contentDataVersion': draft.contentDataVersion,
    'schemaVersions': draft.schemaVersions,
    'logTail': draft.logTail ?? '',
    'clientTs': DateTime.now().toUtc().toIso8601String(),
  };
}

/// 提交反馈到 Cloudflare Worker。
///
/// [baseUrl] 和 [client] 可注入，便于测试。
Future<FeedbackSubmitResult> submitFeedbackToWorker({
  required FeedbackDraft draft,
  String? baseUrl,
  http.Client? client,
}) async {
  final url = '${baseUrl ?? FeedbackConfig.workerBaseUrl}/api/feedback';
  final payload = buildFeedbackPayload(draft);
  final httpClient = client ?? http.Client();

  try {
    final response = await httpClient
        .post(
          Uri.parse(url),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 15));

    Map<String, dynamic> decoded;
    try {
      decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return FeedbackSubmitResult(
        ok: false,
        error: '提交失败（HTTP ${response.statusCode}）',
      );
    }

    if (response.statusCode == 200 && decoded['ok'] == true) {
      return FeedbackSubmitResult(
        ok: true,
        id: decoded['id'] as String?,
      );
    }

    return FeedbackSubmitResult(
      ok: false,
      error: decoded['error'] as String? ?? '提交失败（HTTP ${response.statusCode}）',
    );
  } catch (e) {
    return FeedbackSubmitResult(
      ok: false,
      error: '无法连接开发者服务：$e',
    );
  } finally {
    if (client == null) {
      httpClient.close();
    }
  }
}
