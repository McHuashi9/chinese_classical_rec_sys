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
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';
import 'package:chinese_classical_rec_sys/engine/profile_repository.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/engine/remote_db_sync.dart';
import 'package:chinese_classical_rec_sys/engine/recommendation.dart';
import 'package:chinese_classical_rec_sys/engine/text_repository.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/service/history_service.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';

void main() {
  NativeBridge? bridge;
  var pythonAvailable = false;

  setUpAll(() {
    bridge = _tryLoadBridge();
    pythonAvailable = _tryPython();
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
      if (!pythonAvailable) {
        markTestSkipped('未找到 python3，无法生成纯内容 fixture');
        return;
      }
      work = Directory.systemTemp.createTempSync('engine_chain_it');
      final db = '${work.path}/classical.db';
      final userDb = '${work.path}/user.db';
      _copyAssetDb(db);
      expect(
        bridge!.dbOpen(db.toNativeUtf8(allocator: calloc),
            userDb.toNativeUtf8(allocator: calloc)),
        BridgeError.ok,
      );
      _initDefaultProfile(bridge!);
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
        final answeredAll = calloc<Int32>();
        final n = b.questionGetByText(t.id, block, 5, answeredAll);
        calloc.free(answeredAll);
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

    test('quiz_get_due_review_count：新库无错题返回 0，与列表通道同源', () {
      // 资产库无用户数据：COUNT 通道与列表通道应一致为空
      // （符号存在性 + ABI 签名验证：lookup 失败/签名错位会在此抛错）
      final b = bridge!;
      expect(b.quizGetDueReviewCount(0), 0);
      final block = calloc<ReviewItemData>(16);
      expect(b.quizGetReviewItems(0, block, 16), 0);
      calloc.free(block);
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
      if (!pythonAvailable) {
        markTestSkipped('未找到 python3，无法生成纯内容 fixture');
        return;
      }
      work = Directory.systemTemp.createTempSync('engine_chain_it');
      final db = '${work.path}/classical.db';
      final userDb = '${work.path}/user.db';
      _copyAssetDb(db);
      expect(
        bridge!.dbOpen(db.toNativeUtf8(allocator: calloc),
            userDb.toNativeUtf8(allocator: calloc)),
        BridgeError.ok,
      );
      _initDefaultProfile(bridge!);
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
      if (!pythonAvailable) {
        markTestSkipped('未找到 python3，无法生成纯内容 fixture');
        return;
      }
      work = Directory.systemTemp.createTempSync('engine_chain_it');
      final db = '${work.path}/classical.db';
      final userDb = '${work.path}/user.db';
      _copyAssetDb(db);
      expect(
        bridge!.dbOpen(db.toNativeUtf8(allocator: calloc),
            userDb.toNativeUtf8(allocator: calloc)),
        BridgeError.ok,
      );
      _initDefaultProfile(bridge!);
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

  group('ProfileRepository（真实 .so + 资产库）', () {
    late Directory work;
    late FfiProfileRepository repo;

    setUp(() {
      if (bridge == null) {
        markTestSkipped('未找到 libchinese_core.so，跳过');
        return;
      }
      if (!pythonAvailable) {
        markTestSkipped('未找到 python3，无法生成纯内容 fixture');
        return;
      }
      work = Directory.systemTemp.createTempSync('engine_chain_profile');
      final db = '${work.path}/classical.db';
      final userDb = '${work.path}/user.db';
      _copyAssetDb(db);
      expect(
        bridge!.dbOpen(db.toNativeUtf8(allocator: calloc),
            userDb.toNativeUtf8(allocator: calloc)),
        BridgeError.ok,
      );
      _initDefaultProfile(bridge!);
      repo = FfiProfileRepository(bridge!);
    });

    tearDown(() {
      bridge?.dbClose();
      try {
        work.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('默认档案存在，CRUD 与切换按 FFI 通道工作', () {
      final initial = repo.listProfiles();
      expect(initial.length, 1);
      expect(initial.first.id, 1);
      expect(initial.first.name, '默认用户');
      expect(repo.activeUserId(), 1);

      final id = repo.createProfile('小明');
      expect(id, greaterThan(1));
      expect(repo.listProfiles().length, 2);

      expect(repo.switchProfile(id!), isTrue);
      expect(repo.activeUserId(), id);

      expect(repo.renameProfile(id, '小红'), isTrue);
      expect(repo.listProfiles().map((p) => p.name), contains('小红'));

      // 当前档案不可删除；切回默认后可软删
      expect(repo.deleteProfile(id), isFalse);
      expect(repo.switchProfile(1), isTrue);
      expect(repo.deleteProfile(id), isTrue);
      expect(repo.listProfiles().length, 1);
    });
  });

  group('AppCoordinator 档案切换（真实 .so + 资产库）', () {
    test('创建/切换档案后当前档案、已读集合、档案列表整体刷新', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final lib = _tryLoadLibrary();
      if (lib == null) {
        markTestSkipped('未找到 libchinese_core.so，先执行 cmake --build build');
        return;
      }
      if (!pythonAvailable) {
        markTestSkipped('未找到 python3，无法生成纯内容 fixture');
        return;
      }
      final work = Directory.systemTemp.createTempSync('engine_chain_switch');
      final dbPath = '${work.path}/classical.db';
      final userPath = '${work.path}/user.db';
      _copyAssetDb(dbPath);

      final coord = AppCoordinator(
        navCtrl: NavigationController(),
        settingsCtrl: SettingsController(),
        readingCtrl: ReadingController(ReadTracker()),
        userCtrl: UserController(),
        readTracker: ReadTracker(),
      );
      addTearDown(() {
        coord.dispose();
        try {
          work.deleteSync(recursive: true);
        } catch (_) {}
      });

      expect(await coord.init(dbPath, userPath, lib), isTrue);
      expect(coord.userCtrl.activeUserId, 1);
      expect(coord.userCtrl.profiles.length, 1);
      expect(coord.userCtrl.activeProfileName, '默认用户');

      // 新建档案并切换：当前档案/列表/名字刷新，新档案已读集合为空
      final id = coord.createProfile('小明');
      expect(id, isNotNull);
      expect(coord.switchProfile(id!), isTrue);
      expect(coord.userCtrl.activeUserId, id);
      expect(coord.userCtrl.profiles.length, 2);
      expect(coord.userCtrl.activeProfileName, '小明');
      expect(coord.readTracker.getAllTrackedIds(), isEmpty);

      // 切回默认档案：状态随之回来
      expect(coord.switchProfile(1), isTrue);
      expect(coord.userCtrl.activeUserId, 1);
      expect(coord.userCtrl.activeProfileName, '默认用户');

      // 重复切换同一档案：幂等成功；切换不存在/已删档案：失败
      expect(coord.switchProfile(1), isTrue);
      expect(coord.switchProfile(9999), isFalse);
    });
  });

  group('AppCoordinator 远程同步失败路径（R1）', () {
    test('db_replace 失败后恢复当前档案，不跨档案污染', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final lib = _tryLoadLibrary();
      if (lib == null) {
        markTestSkipped('未找到 libchinese_core.so，先执行 cmake --build build');
        return;
      }
      if (!pythonAvailable) {
        markTestSkipped('未找到 python3，无法生成纯内容 fixture');
        return;
      }
      final work = Directory.systemTemp.createTempSync('engine_chain_sync_fail');
      _copyAssetDb('${work.path}/classical.db');
      final dbPath = '${work.path}/classical.db';
      final userPath = '${work.path}/user.db';

      final coord = AppCoordinator(
        navCtrl: NavigationController(),
        settingsCtrl: SettingsController(),
        readingCtrl: ReadingController(ReadTracker()),
        userCtrl: UserController(),
        readTracker: ReadTracker(),
      );
      addTearDown(() {
        coord.dispose();
        try {
          work.deleteSync(recursive: true);
        } catch (_) {}
      });

      expect(await coord.init(dbPath, userPath, lib), isTrue);

      // 切到小明，并让 prefs 记住当前档案
      final id = coord.createProfile('小明');
      expect(id, isNotNull);
      expect(coord.switchProfile(id!), isTrue);
      await prefs.setInt('active_user_id', id);
      expect(coord.userCtrl.activeProfileName, '小明');

      // MockClient 下载一个非 SQLite 的 tmp 文件，db_replace 必然失败
      final sync = RemoteDbSync(prefs, work.path,
          client: MockClient((_) async => http.Response('not a sqlite db', 200)));
      coord.setContentPathAfterSync(dbPath);
      coord.initRemoteDbSync(prefs, work.path, remoteDbSync: sync);

      await coord.remoteSyncDb(
        remoteVersion: '20990101-deadbeef',
        downloadUrl: 'http://example.com/classical.db',
      );

      // 失败后引擎与内存都应恢复为小明，而不是默认档案 1
      expect(coord.userCtrl.activeUserId, id);
      expect(coord.userCtrl.activeProfileName, '小明');
      expect(FfiProfileRepository(coord.bridge!).activeUserId(), id);
      expect(coord.settingsCtrl.error, contains('数据库同步失败'));
    });

    test('同步成功路径：db_replace 后不重开引擎/不重载档案，当前用户保持', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final lib = _tryLoadLibrary();
      if (lib == null) {
        markTestSkipped('未找到 libchinese_core.so，先执行 cmake --build build');
        return;
      }
      if (!pythonAvailable) {
        markTestSkipped('未找到 python3，无法生成纯内容 fixture');
        return;
      }
      final work = Directory.systemTemp.createTempSync('engine_chain_sync_ok');
      _copyAssetDb('${work.path}/classical.db');
      _copyAssetDb('${work.path}/new_classical.db');
      final dbPath = '${work.path}/classical.db';
      final userPath = '${work.path}/user.db';

      final coord = AppCoordinator(
        navCtrl: NavigationController(),
        settingsCtrl: SettingsController(),
        readingCtrl: ReadingController(ReadTracker()),
        userCtrl: UserController(),
        readTracker: ReadTracker(),
      );
      addTearDown(() {
        coord.dispose();
        try {
          work.deleteSync(recursive: true);
        } catch (_) {}
      });

      expect(await coord.init(dbPath, userPath, lib), isTrue);
      final id = coord.createProfile('小明');
      expect(id, isNotNull);
      expect(coord.switchProfile(id!), isTrue);
      await prefs.setInt('active_user_id', id);

      final newBytes = File('${work.path}/new_classical.db').readAsBytesSync();
      final sync = RemoteDbSync(prefs, work.path,
          client: MockClient((_) async => http.Response.bytes(newBytes, 200)));
      coord.setContentPathAfterSync(dbPath);
      coord.initRemoteDbSync(prefs, work.path, remoteDbSync: sync);

      await coord.remoteSyncDb(
        remoteVersion: '20990101-deadbeef',
        downloadUrl: 'http://example.com/classical.db',
      );

      expect(coord.settingsCtrl.error, isNull);
      expect(coord.settingsCtrl.notice, contains('内容已更新'));
      expect(coord.userCtrl.activeUserId, id);
      expect(coord.userCtrl.activeProfileName, '小明');
      expect(FfiProfileRepository(coord.bridge!).activeUserId(), id);
    });
  });
}

// ─── helpers ──────────────────────────────────────────────────────────────

DynamicLibrary? _tryLoadLibrary() {
  final candidates = [
    '../build/libchinese_core.so',
    '../build/tests/libchinese_core.so',
    'build/libchinese_core.so',
  ];
  for (final p in candidates) {
    final f = File(p);
    if (f.existsSync()) {
      return DynamicLibrary.open(f.absolute.path);
    }
  }
  return null;
}

NativeBridge? _tryLoadBridge() {
  final lib = _tryLoadLibrary();
  return lib == null ? null : NativeBridge.fromLib(lib);
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
  final script = _fixtureScriptPath();
  final result = Process.runSync(
      'python3', [script, _assetDbPath(), dest]);
  if (result.exitCode != 0) {
    throw StateError('生成纯内容 fixture 失败: ${result.stderr}');
  }
}

/// 完成默认档案强制初始化（6 题统一选 0）。已初始化时跳过。
void _initDefaultProfile(NativeBridge b) {
  if (b.userIsInitialized() > 0) return;
  final block = calloc<QuestionData>(8);
  final n = b.userInitQuestions(block, 8);
  if (n <= 0) {
    calloc.free(block);
    throw StateError('无法获取初始化题');
  }
  final qids = calloc<Int32>(n);
  final choices = calloc<Int32>(n);
  for (int i = 0; i < n; i++) {
    qids[i] = (block + i).ref.id;
    choices[i] = 0;
  }
  final out = calloc<UserData>();
  final rc = b.userInitApply(qids, choices, n, 1700000000, out);
  calloc.free(qids);
  calloc.free(choices);
  calloc.free(out);
  calloc.free(block);
  if (rc != BridgeError.ok) {
    throw StateError('初始化默认档案失败 rc=$rc');
  }
}

String _fixtureScriptPath() {
  for (final p in [
    'test/helpers/make_content_fixture.py',
    '../flutter_app/test/helpers/make_content_fixture.py',
  ]) {
    if (File(p).existsSync()) return p;
  }
  throw StateError('找不到 make_content_fixture.py');
}

bool _tryPython() {
  try {
    final r = Process.runSync('python3', ['--version']);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}
