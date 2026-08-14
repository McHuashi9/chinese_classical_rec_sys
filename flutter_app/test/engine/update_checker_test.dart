import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/engine/update_checker.dart';
import 'package:chinese_classical_rec_sys/models/version.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late int nowMs;

  setUp(() async {
    nowMs = DateTime.now().millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  UpdateChecker checker(MockClient client) =>
      UpdateChecker(prefs, client: client);

  group('checkSilently（24h 自动检查）', () {
    test('冷却期内不发起请求，返回 null', () async {
      await prefs.setInt(UpdateChecker.prefKeyLastCheck, nowMs);
      var calls = 0;
      final c = MockClient((_) async {
        calls++;
        return http.Response('', 500);
      });
      final result = await checker(c).checkSilently('0.9.1');
      expect(result, isNull);
      expect(calls, 0);
    });

    test('无冷却记录时发起请求，远端更新则返回新版本', () async {
      final c = MockClient((_) async => http.Response(
            jsonEncode({'tag_name': 'v9.9.9'}),
            200,
            headers: {'etag': '"abc"'},
          ));
      final result = await checker(c).checkSilently('0.9.1');
      expect(result, const Version(9, 9, 9));
    });

    test('远端版本不高于当前版本时返回 null', () async {
      final c = MockClient((_) async => http.Response(
            jsonEncode({'tag_name': 'v0.9.0'}),
            200,
            headers: {'etag': '"abc"'},
          ));
      final result = await checker(c).checkSilently('0.9.1');
      expect(result, isNull);
    });

    test('限流期内跳过，不发起请求', () async {
      await prefs.setInt(UpdateChecker.prefKeyRateLimitedUntil, nowMs + 3600000);
      var calls = 0;
      final c = MockClient((_) async {
        calls++;
        return http.Response('', 500);
      });
      final result = await checker(c).checkSilently('0.9.1');
      expect(result, isNull);
      expect(calls, 0);
    });

    test('成功后写入 last_check，下次静默检查进入冷却', () async {
      final c = MockClient((_) async => http.Response(
            jsonEncode({'tag_name': 'v9.9.9'}),
            200,
            headers: {'etag': '"abc"'},
          ));
      await checker(c).checkSilently('0.9.1');
      expect(prefs.getInt(UpdateChecker.prefKeyLastCheck), isNotNull);

      var calls2 = 0;
      final c2 = MockClient((_) async {
        calls2++;
        return http.Response('', 500);
      });
      final again = await checker(c2).checkSilently('0.9.1');
      expect(again, isNull);
      expect(calls2, 0);
    });
  });

  group('checkManually（手动检查）', () {
    test('5 分钟内重复手动检查被拒绝', () async {
      await prefs.setInt(UpdateChecker.prefKeyLastManual, nowMs - 60000);
      final c = MockClient((_) async => http.Response('', 500));
      final chk = checker(c);
      final result = await chk.checkManually('0.9.1');
      expect(result, isNull);
      expect(chk.lastErrorReason, '操作太频繁，请稍后再试');
    });

    test('限流期内手动检查被拒绝', () async {
      await prefs.setInt(UpdateChecker.prefKeyRateLimitedUntil, nowMs + 3600000);
      final c = MockClient((_) async => http.Response('', 500));
      final chk = checker(c);
      final result = await chk.checkManually('0.9.1');
      expect(result, isNull);
      expect(chk.lastErrorReason, '请求已被限流，请一小时后重试');
    });

    test('成功后返回新版本并写入 last_check/last_manual', () async {
      final c = MockClient((_) async => http.Response(
            jsonEncode({'tag_name': 'v9.9.9'}),
            200,
            headers: {'etag': '"abc"'},
          ));
      final result = await checker(c).checkManually('0.9.1');
      expect(result, const Version(9, 9, 9));
      expect(prefs.getInt(UpdateChecker.prefKeyLastCheck), isNotNull);
      expect(prefs.getInt(UpdateChecker.prefKeyLastManual), isNotNull);
    });

    test('拉取失败不写 last_manual，可立即重试（不冷却 5 分钟）', () async {
      var succeed = false;
      final c = MockClient((_) async => succeed
          ? http.Response(jsonEncode({'tag_name': 'v9.9.9'}), 200,
              headers: {'etag': '"abc"'})
          : http.Response('', 500));
      final chk = checker(c);
      final failed = await chk.checkManually('0.9.1');
      expect(failed, isNull);
      expect(prefs.getInt(UpdateChecker.prefKeyLastManual), isNull);

      // 未拨冷却时间也能立刻重试成功（修复前会被 5 分钟手动冷却拦截）
      succeed = true;
      final ok = await chk.checkManually('0.9.1');
      expect(ok, const Version(9, 9, 9));
      expect(prefs.getInt(UpdateChecker.prefKeyLastManual), isNotNull);
    });

test('新一轮手动检查前清空上次失败原因', () async {
      var succeed = false;
      final c = MockClient((_) async => succeed
          ? http.Response(jsonEncode({'tag_name': 'v9.9.9'}), 200,
              headers: {'etag': '"abc"'})
          : http.Response('', 500));
      final chk = checker(c);
      await chk.checkManually('0.9.1');
      expect(chk.lastErrorReason, '服务器返回异常 (HTTP 500)');

      // 拨回冷却时间，避免第二次被 5 分钟手动冷却拦截
      await prefs.setInt(UpdateChecker.prefKeyLastManual, nowMs - 600000);
      succeed = true;
      await chk.checkManually('0.9.1');
      expect(chk.lastErrorReason, isNull);
    });
  });

  group('GitHub API 响应处理', () {
    test('200 + tag_name：返回版本并缓存 etag 与 tag', () async {
      final c = MockClient((_) async => http.Response(
            jsonEncode({'tag_name': 'v0.9.1'}),
            200,
            headers: {'etag': '"abc123"'},
          ));
      final result = await checker(c).checkManually('0.8.0');
      expect(result, const Version(0, 9, 1));
      expect(prefs.getString(UpdateChecker.prefKeyEtag), '"abc123"');
      expect(prefs.getString(UpdateChecker.prefKeyTagName), 'v0.9.1');
    });

    test('304 + 本地缓存 tag：返回缓存版本', () async {
      await prefs.setString(UpdateChecker.prefKeyTagName, 'v0.9.1');
      final c = MockClient((_) async => http.Response('', 304));
      final result = await checker(c).checkManually('0.8.0');
      expect(result, const Version(0, 9, 1));
    });

    test('304 但无本地缓存：报错返回 null', () async {
      final c = MockClient((_) async => http.Response('', 304));
      final chk = checker(c);
      final result = await chk.checkManually('0.8.0');
      expect(result, isNull);
      expect(chk.lastErrorReason, '服务器返回未修改，但本地无缓存版本');
    });

    test('403：写入 1 小时退避并设置原因', () async {
      final c = MockClient((_) async => http.Response('', 403));
      final chk = checker(c);
      final result = await chk.checkManually('0.8.0');
      expect(result, isNull);
      expect(
        prefs.getInt(UpdateChecker.prefKeyRateLimitedUntil),
        greaterThan(nowMs + 3599000),
      );
      expect(chk.lastErrorReason, 'API 请求被限流，请一小时后重试');
    });

    test('非 200：设置 HTTP 状态原因', () async {
      final c = MockClient((_) async => http.Response('', 500));
      final chk = checker(c);
      final result = await chk.checkManually('0.8.0');
      expect(result, isNull);
      expect(chk.lastErrorReason, '服务器返回异常 (HTTP 500)');
    });

    test('x-ratelimit-remaining <= 5：退避 1 小时', () async {
      final c = MockClient((_) async =>
          http.Response('', 200, headers: {'x-ratelimit-remaining': '3'}));
      final chk = checker(c);
      final result = await chk.checkManually('0.8.0');
      expect(result, isNull);
      expect(
        prefs.getInt(UpdateChecker.prefKeyRateLimitedUntil),
        greaterThan(nowMs + 3599000),
      );
      expect(chk.lastErrorReason, 'API 请求次数已达上限，请一小时后重试');
    });

    test('请求抛异常：网络不可用原因', () async {
      final c = MockClient((_) async => throw Exception('conn refused'));
      final chk = checker(c);
      final result = await chk.checkManually('0.8.0');
      expect(result, isNull);
      expect(chk.lastErrorReason, '网络不可用，请检查连接后重试');
    });

    test('设置 token 后请求带 Authorization 头', () async {
      late http.Request captured;
      final c = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'tag_name': 'v9.9.9'}),
          200,
          headers: {'etag': '"e"'},
        );
      });
      final chk = checker(c);
      chk.setToken('tok123');
      await chk.checkManually('0.8.0');
      expect(captured.headers['Authorization'], 'Bearer tok123');
    });

    test('已有 etag 时请求带 If-None-Match 头', () async {
      await prefs.setString(UpdateChecker.prefKeyEtag, '"old"');
      late http.Request captured;
      final c = MockClient((request) async {
        captured = request;
        return http.Response('', 304);
      });
      await checker(c).checkManually('0.8.0');
      expect(captured.headers['If-None-Match'], '"old"');
    });
  });
}
