// FFI 集成测试：真实加载 libchinese_core.so（C++ 引擎），在临时目录模拟
// 启动/同步的关键文件状态，验证 db_replace / db_open 的崩溃安全与数据保真。
//
// 依赖：需先构建核心（`cmake --build build --target chinese_core` 或 run_tests）。
// 未找到 .so 时自动跳过（CI 的 Windows/Android/iOS 作业无 Linux 产物，不挂 CI）。
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';

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

  group('db_replace FFI 集成（需本机核心产物）', () {
    late Directory work;

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
      work = Directory.systemTemp.createTempSync('db_replace_it');
    });

    tearDown(() {
      bridge?.dbClose();
      try {
        work.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('.bak 恢复 + 版本 unknown + 内置数据升级：用户数据保留、自增序列对齐', () {
      final b = bridge!;
      final db = '${work.path}/classical.db';
      _copyAssetDb(db);
      expect(b.dbOpen(db.toNativeUtf8(allocator: calloc), '${work.path}/user.db'.toNativeUtf8(allocator: calloc)), BridgeError.ok);
      _initDefaultProfile(b);

      _saveUser(b, 0.6);
      expect(b.historyAddRecord(1, 60.0, 1700000000), BridgeError.ok);
      b.dbClose();

      // 模拟崩溃落点：正式库缺失、仅剩 .bak（swap 在"旧库→.bak"后中断）
      File('${work.path}/classical.db.bak')
          .writeAsBytesSync(File(db).readAsBytesSync());
      File(db).deleteSync();
      expect(File(db).existsSync(), isFalse);

      // Dart 启动逻辑：.bak 恢复 + 版本标 unknown
      File('${work.path}/classical.db.bak').renameSync(db);
      File('${work.path}/db_version.txt').writeAsStringSync('unknown');

      // 恢复后的库可正常打开，数据完好
      expect(b.dbOpen(db.toNativeUtf8(allocator: calloc), '${work.path}/user.db'.toNativeUtf8(allocator: calloc)), BridgeError.ok);
      _initDefaultProfile(b);
      expect(b.textGetCount(), 270);
      expect(b.historyGetTotalCount(), 1);
      _expectUserBase(b, 0.6);
      b.dbClose();

      // 方向判断：asset 版本比 unknown 新 → 内置数据升级（db_replace 合并用户数据）
      final tmp = '${work.path}/classical.db.tmp';
      _copyAssetDb(tmp);
      expect(b.dbReplace(tmp.toNativeUtf8(allocator: calloc),
          db.toNativeUtf8(allocator: calloc)), BridgeError.ok);
      expect(b.dbOpen(db.toNativeUtf8(allocator: calloc), '${work.path}/user.db'.toNativeUtf8(allocator: calloc)), BridgeError.ok);
      _initDefaultProfile(b);
      expect(b.textGetCount(), 270);
      expect(b.historyGetTotalCount(), 1);
      _expectUserBase(b, 0.6);

      // 自增序列对齐：新记录 id 不与合并导入的 id 冲突
      expect(b.historyAddRecord(2, 30.0, 1700000010), BridgeError.ok);
      expect(b.historyGetTotalCount(), 2);
    });

    test('swap 中断落点（cur 缺失、bak=旧库、tmp=新库）：启动自愈且不丢数据', () {
      final b = bridge!;
      final db = '${work.path}/classical.db';
      _copyAssetDb(db);
      expect(b.dbOpen(db.toNativeUtf8(allocator: calloc), '${work.path}/user.db'.toNativeUtf8(allocator: calloc)), BridgeError.ok);
      _initDefaultProfile(b);
      _saveUser(b, 0.5);
      expect(b.historyAddRecord(3, 90.0, 1700000000), BridgeError.ok);
      b.dbClose();

      // 构造 swap 进行到一半的文件状态：旧库在 .bak，新库已下载到 .tmp，正式位缺失
      File('${work.path}/classical.db.bak')
          .writeAsBytesSync(File(db).readAsBytesSync());
      File(db).deleteSync();
      _copyAssetDb('${work.path}/classical.db.tmp');
      expect(File(db).existsSync(), isFalse);

      // 启动：.bak → 正式位，版本 unknown，随后 asset 更新方向判定走 db_replace
      File('${work.path}/classical.db.bak').renameSync(db);
      File('${work.path}/db_version.txt').writeAsStringSync('unknown');
      expect(b.dbReplace('${work.path}/classical.db.tmp'.toNativeUtf8(allocator: calloc),
          db.toNativeUtf8(allocator: calloc)), BridgeError.ok);
      expect(b.dbOpen(db.toNativeUtf8(allocator: calloc), '${work.path}/user.db'.toNativeUtf8(allocator: calloc)), BridgeError.ok);
      _initDefaultProfile(b);

      expect(b.textGetCount(), 270);
      expect(b.historyGetTotalCount(), 1);
      _expectUserBase(b, 0.5);
      // 替换成功后 .bak 已由 db_replace 清理
      expect(File('${work.path}/classical.db.bak').existsSync(), isFalse);
    });

    test('无效新库回滚：替换失败后旧库字节不变、引擎可重开、数据完好', () {
      final b = bridge!;
      final db = '${work.path}/classical.db';
      _copyAssetDb(db);
      expect(b.dbOpen(db.toNativeUtf8(allocator: calloc), '${work.path}/user.db'.toNativeUtf8(allocator: calloc)), BridgeError.ok);
      _initDefaultProfile(b);
      _saveUser(b, 0.8);
      expect(b.historyAddRecord(4, 45.0, 1700000000), BridgeError.ok);

      final beforeBytes = File(db).readAsBytesSync();

      // 伪造损坏的新库（非 SQLite 内容）
      final tmp = '${work.path}/classical.db.tmp';
      File(tmp).writeAsBytesSync('this is not a sqlite database at all....'.codeUnits);

      final rc = b.dbReplace(tmp.toNativeUtf8(allocator: calloc),
          db.toNativeUtf8(allocator: calloc));
      expect(rc, isNot(BridgeError.ok));

      // 旧库字节级不变，且未产生 .bak（失败发生在文件层替换之前）
      expect(File(db).readAsBytesSync(), beforeBytes);
      expect(File('${work.path}/classical.db.bak').existsSync(), isFalse);
      // tmp 由 Dart 侧失败路径删除
      File(tmp).deleteSync();

      // 引擎可重开（H2 恢复路径），数据完好
      expect(b.dbOpen(db.toNativeUtf8(allocator: calloc), '${work.path}/user.db'.toNativeUtf8(allocator: calloc)), BridgeError.ok);
      _initDefaultProfile(b);
      expect(b.textGetCount(), 270);
      expect(b.historyGetTotalCount(), 1);
      _expectUserBase(b, 0.8);
    });
  });

  group('text_get_translation FFI 集成（需本机核心产物）', () {
    late Directory work;

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
      work = Directory.systemTemp.createTempSync('translation_it');
    });

    tearDown(() {
      bridge?.dbClose();
      try {
        work.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('真实资产库返回非空译文', () {
      final b = bridge!;
      final db = '${work.path}/classical.db';
      _copyAssetDb(db);
      expect(b.dbOpen(db.toNativeUtf8(allocator: calloc), '${work.path}/user.db'.toNativeUtf8(allocator: calloc)), BridgeError.ok);
      _initDefaultProfile(b);

      final out = calloc<Uint8>(65536);
      final rc = b.textGetTranslation(1, out.cast<Utf8>(), 65536);
      expect(rc, BridgeError.ok);

      final bytes = <int>[];
      for (int i = 0; i < 65536; i++) {
        if (out[i] == 0) break;
        bytes.add(out[i]);
      }
      calloc.free(out);
      expect(utf8.decode(bytes), isNotEmpty);
    });

    test('不存在 id 返回 BRIDGE_ERR_TEXT', () {
      final b = bridge!;
      final db = '${work.path}/classical.db';
      _copyAssetDb(db);
      expect(b.dbOpen(db.toNativeUtf8(allocator: calloc), '${work.path}/user.db'.toNativeUtf8(allocator: calloc)), BridgeError.ok);
      _initDefaultProfile(b);

      final out = calloc<Uint8>(1024);
      final rc = b.textGetTranslation(999999, out.cast<Utf8>(), 1024);
      calloc.free(out);
      expect(rc, BridgeError.errText);
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
      return NativeBridge.fromLib(
          DynamicLibrary.open(f.absolute.path));
    }
  }
  return null;
}

String _assetDbPath() {
  for (final p in ['assets/data/classical.db', '../flutter_app/assets/data/classical.db']) {
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

void _saveUser(NativeBridge b, double base) {
  final u = calloc<UserData>();
  u.ref.lastReadTime = 1700000000;
  for (var i = 0; i < 10; i++) {
    u.ref.abilities[i] = base + i * 0.01;
    u.ref.baseAbilities[i] = base + i * 0.01;
  }
  expect(b.userSave(u), BridgeError.ok);
  calloc.free(u);
}

void _expectUserBase(NativeBridge b, double base) {
  final u = calloc<UserData>();
  expect(b.userLoad(u), BridgeError.ok);
  for (var i = 0; i < 10; i++) {
    expect(u.ref.baseAbilities[i], closeTo(base + i * 0.01, 1e-9));
  }
  calloc.free(u);
}
