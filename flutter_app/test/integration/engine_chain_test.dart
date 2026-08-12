// FFI 集成测试：真实加载 libchinese_core.so（C++ 引擎），用资产库走通
// 文本仓库 / 推荐 / 阅读历史 三条 Dart 封装链路（单测无法构造 NativeBridge，
// 此处补 recommendation.dart / text_repository.dart / history_service.dart 的 FFI 路径）。
//
// 依赖：需先构建核心（`cmake --build build --target chinese_core` 或 run_tests）。
// 未找到 .so 时自动跳过（CI 的 Windows/Android/iOS 作业无 Linux 产物，不挂 CI）。
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';
import 'package:chinese_classical_rec_sys/engine/recommendation.dart';
import 'package:chinese_classical_rec_sys/engine/text_repository.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/service/history_service.dart';

void main() {
  NativeBridge? bridge;

  setUpAll(() {
    bridge = _tryLoadBridge();
  });

  tearDown(() {
    bridge?.dbClose();
  });

  group('TextRepository（真实 .so + 资产库）', () {
    late Directory work;
    late TextRepository repo;

    setUp(() {
      if (bridge == null) {
        markTestSkipped(
            '未找到 libchinese_core.so，先执行 cmake --build build（CI 非 Linux 作业自动跳过）');
        return;
      }
      work = Directory.systemTemp.createTempSync('engine_chain_it');
      final db = '${work.path}/classical.db';
      _copyAssetDb(db);
      expect(bridge!.dbOpen(db.toNativeUtf8(allocator: calloc)), BridgeError.ok);
      repo = TextRepository(bridge!);
      repo.loadTextCache();
    });

    tearDown(() {
      try {
        work.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('loadTextCache 加载全部文章，texts/textCount 一致', () {
      expect(repo.textCount, greaterThan(0));
      expect(repo.texts.length, repo.textCount);
      expect(repo.texts.first.title, isNotEmpty);
      expect(repo.texts.first.author, isNotEmpty);
      expect(repo.texts.first.dynasty, isNotEmpty);
    });

    test('getTextDetail 返回正文/字数，未知 id 返回 null', () {
      final first = repo.texts.first;
      final detail = repo.getTextDetail(first.id);
      expect(detail, isNotNull);
      expect(detail!.content, isNotEmpty);
      expect(detail.charCount, greaterThan(0));
      expect(detail.difficulties.length, 10);

      expect(repo.getTextDetail(999999), isNull);
    });

    test('getAnnotations/getTranslation 不抛错（允许空串降级）', () {
      final first = repo.texts.first;
      expect(repo.getAnnotations(first.id), isA<String>());
      expect(repo.getTranslation(first.id), isA<String>());
    });

    test('重复 loadTextCache 覆盖而非追加', () {
      repo.loadTextCache();
      final before = repo.textCount;
      repo.loadTextCache();
      expect(repo.textCount, before);
    });

    test('question_get_by_text 划线语境跨 ABI 完整（C 写 Dart 读）', () {
      // 真 .so + 资产库：结构化校验 context/mark 区间（仅当问句带原句）
      final b = bridge!;
      var verified = 0;
      for (final t in repo.texts) {
        final block = calloc<QuestionData>(5);
        final n = b.questionGetByText(t.id, block, 5);
        if (n <= 0) {
          calloc.free(block);
          continue;
        }
        for (var i = 0; i < n; i++) {
          final q = Question(block + i, owner: block);
          final ctx = q.context;
          if (ctx.isEmpty) {
            expect(q.markStart, -1);
            expect(q.markLen, 0);
          } else {
            expect(q.markStart, greaterThanOrEqualTo(0));
            expect(q.markStart + q.markLen, lessThanOrEqualTo(ctx.length));
            expect(
              ctx.substring(q.markStart, q.markStart + q.markLen),
              isNot(contains('〔')),
              reason: '划线区间不应含注释标记',
            );
            verified++;
          }
        }
        calloc.free(block);
        if (verified >= 3) break;
      }
      expect(verified, greaterThan(0), reason: '资产库应存在带原句的题目');
    });
  });

  group('RecommendationEngine（真实 .so + 资产库）', () {
    late Directory work;
    late TextRepository repo;
    late User user;

    setUp(() {
      if (bridge == null) {
        markTestSkipped('未找到 libchinese_core.so，跳过');
        return;
      }
      work = Directory.systemTemp.createTempSync('engine_chain_it');
      _copyAssetDb('${work.path}/classical.db');
      expect(bridge!.dbOpen('${work.path}/classical.db'.toNativeUtf8(allocator: calloc)),
          BridgeError.ok);
      repo = TextRepository(bridge!);
      repo.loadTextCache();
      user = User.allocate(calloc);
    });

    tearDown(() {
      user.dispose();
      try {
        work.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('返回 topK 条且概率降序，id 均能在缓存中找到', () {
      final engine = RecommendationEngine(bridge!);
      final results = engine.getRecommendations(user, 5, repo.texts);
      expect(results.length, 5);
      for (var i = 1; i < results.length; i++) {
        expect(
          results[i].probability <= results[i - 1].probability,
          isTrue,
          reason: '推荐结果应按概率降序',
        );
      }
      final cacheIds = repo.texts.map((t) => t.id).toSet();
      for (final r in results) {
        expect(cacheIds.contains(r.text.id), isTrue);
        expect(r.text.title, isNotEmpty);
      }
    });

    test('topK 大于文章数时全部返回', () {
      final engine = RecommendationEngine(bridge!);
      final results =
          engine.getRecommendations(user, 99999, repo.texts);
      expect(results.length, repo.textCount);
    });
  });

  group('HistoryService（真实 .so + 资产库）', () {
    late Directory work;
    late TextRepository repo;

    setUp(() {
      if (bridge == null) {
        markTestSkipped('未找到 libchinese_core.so，跳过');
        return;
      }
      work = Directory.systemTemp.createTempSync('engine_chain_it');
      _copyAssetDb('${work.path}/classical.db');
      expect(bridge!.dbOpen('${work.path}/classical.db'.toNativeUtf8(allocator: calloc)),
          BridgeError.ok);
      repo = TextRepository(bridge!);
      repo.loadTextCache();
    });

    tearDown(() {
      try {
        work.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('写入记录后 getRecent 带出标题，computeStats 正确', () {
      final b = bridge!;
      final first = repo.texts.first;
      expect(b.historyAddRecord(first.id, 120.0, 1700000000), BridgeError.ok);
      expect(b.historyAddRecord(first.id, 60.0, 1700003600), BridgeError.ok);

      final history = HistoryService(b, repo);
      expect(history.getTotalCount(), 2);
      final recent = history.getRecent(10);
      expect(recent.length, 2);
      expect(recent.first.textId, first.id);
      expect(recent.first.title, isNot('(未知)'));
      expect(recent.first.title, first.title);
      expect(recent.first.author, first.author);

      // 同日两条 → 日均按 1 天，篇数去重为 1
      final stats = HistoryService.computeStats(recent);
      expect(stats.totalSeconds, 180);
      expect(stats.totalTexts, 1);
      expect(stats.dailyAvgSeconds, 180.0);
      expect(stats.longestStreak, 1);
    });

    test('无记录时 getRecent 返回空、统计全零', () {
      final history = HistoryService(bridge!, repo);
      expect(history.getTotalCount(), 0);
      expect(history.getRecent(10), isEmpty);
      final stats = HistoryService.computeStats(const []);
      expect(stats.totalSeconds, 0);
      expect(stats.longestStreak, 0);
    });
  });
}

// ─── helpers ──────────────────────────────────────────────────────────────

NativeBridge? _tryLoadBridge() {
  final candidates = [
    '../build/libchinese_core.so',
    '../build/tests/libchinese_core.so',
    'build/libchinese_core.so',
  ];
  for (final p in candidates) {
    final f = File(p);
    if (f.existsSync()) {
      return NativeBridge.fromLib(DynamicLibrary.open(f.absolute.path));
    }
  }
  return null;
}

String _assetDbPath() {
  for (final p in [
    'assets/data/classical.db',
    '../flutter_app/assets/data/classical.db',
  ]) {
    if (File(p).existsSync()) return p;
  }
  throw StateError('找不到资产 DB（assets/data/classical.db）');
}

void _copyAssetDb(String dest) {
  File(dest).writeAsBytesSync(File(_assetDbPath()).readAsBytesSync());
}
