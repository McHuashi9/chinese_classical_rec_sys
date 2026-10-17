import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/engine/db_path_resolver.dart';

void main() {
  late Directory temp;
  late Uint8List assetDb;
  late String assetVersion;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('db_path_resolver_test_');
    assetDb = Uint8List.fromList(<int>[10, 20, 30, 40]);
    assetVersion = '202608101200-abc';
  });

  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  DbPathResolver buildResolver({
    DbReplaceCallback? dbReplace,
    SupportDirectoryProvider? supportDirectoryProvider,
    AssetBytesLoader? assetBytesLoader,
    AssetStringLoader? assetStringLoader,
  }) {
    return DbPathResolver(
      supportDirectoryProvider: supportDirectoryProvider ?? () async => temp,
      assetBytesLoader:
          assetBytesLoader ?? (_) async => Uint8List.fromList(assetDb),
      assetStringLoader: assetStringLoader ?? (_) async => assetVersion,
      dbReplace: dbReplace ?? (_, __) => BridgeError.ok,
    );
  }

  test('全新安装写入资产 DB 与版本文件', () async {
    final resolution = await buildResolver().resolve();

    expect(resolution.replaced, isFalse);
    expect(resolution.contentPath, '${temp.path}/classical.db');
    expect(resolution.userPath, '${temp.path}/user.db');
    expect(File(resolution.contentPath).readAsBytesSync(), assetDb);
    expect(
        File('${temp.path}/db_version.txt').readAsStringSync(), assetVersion);
  });

  test('.bak 恢复为正式库且版本标 unknown', () async {
    assetVersion = 'unknown';
    final bak = File('${temp.path}/classical.db.bak')
      ..writeAsBytesSync(<int>[7, 8, 9]);

    final resolution = await buildResolver().resolve();

    expect(resolution.replaced, isFalse);
    expect(bak.existsSync(), isFalse);
    expect(File(resolution.contentPath).readAsBytesSync(), <int>[7, 8, 9]);
    expect(File('${temp.path}/db_version.txt').readAsStringSync(), 'unknown');
  });

  test('清理上次会话遗留的 .tmp', () async {
    assetVersion = 'unknown';
    File('${temp.path}/classical.db').writeAsBytesSync(<int>[1]);
    final tmp = File('${temp.path}/classical.db.tmp')
      ..writeAsBytesSync(<int>[2]);

    await buildResolver().resolve();

    expect(tmp.existsSync(), isFalse);
  });

  test('内置资产更新：写 tmp、调用 replace、成功回写版本', () async {
    File('${temp.path}/classical.db').writeAsBytesSync(<int>[1, 2]);
    File('${temp.path}/db_version.txt').writeAsStringSync('202601010000-0a0');
    String? seenNewPath;
    String? seenCurrentPath;
    Uint8List? seenTmpBytes;

    final resolution = await buildResolver(
      dbReplace: (newPath, currentPath) {
        seenNewPath = newPath;
        seenCurrentPath = currentPath;
        seenTmpBytes = File(newPath).readAsBytesSync();
        // 生产 C++ db_replace 成功时会把 tmp 移动到正式位。
        File(newPath).deleteSync();
        return BridgeError.ok;
      },
    ).resolve();

    expect(resolution.replaced, isTrue);
    expect(seenNewPath, '${temp.path}/classical.db.tmp');
    expect(seenCurrentPath, '${temp.path}/classical.db');
    expect(seenTmpBytes, assetDb);
    expect(
        File('${temp.path}/db_version.txt').readAsStringSync(), assetVersion);
    expect(File('${temp.path}/classical.db.tmp').existsSync(), isFalse,
        reason: '成功替换后 tmp 由引擎侧消费');
  });

  test('内置资产替换失败：旧库与旧版本保留，tmp 清理', () async {
    final oldBytes = <int>[1, 2, 3];
    File('${temp.path}/classical.db').writeAsBytesSync(oldBytes);
    File('${temp.path}/db_version.txt').writeAsStringSync('202601010000-0a0');

    final resolution = await buildResolver(
      dbReplace: (_, __) => BridgeError.errGeneric,
    ).resolve();

    expect(resolution.replaced, isFalse);
    expect(File(resolution.contentPath).readAsBytesSync(), oldBytes);
    expect(File('${temp.path}/db_version.txt').readAsStringSync(),
        '202601010000-0a0');
    expect(File('${temp.path}/classical.db.tmp').existsSync(), isFalse);
  });

  test('内置资产不新于本地：不调用 replace，并清理无用途 .bak', () async {
    File('${temp.path}/classical.db').writeAsBytesSync(<int>[1]);
    File('${temp.path}/db_version.txt').writeAsStringSync(assetVersion);
    final bak = File('${temp.path}/classical.db.bak')
      ..writeAsBytesSync(<int>[2]);
    var replaceCalled = false;

    final resolution = await buildResolver(
      dbReplace: (_, __) {
        replaceCalled = true;
        return BridgeError.ok;
      },
    ).resolve();

    expect(resolution.replaced, isFalse);
    expect(replaceCalled, isFalse);
    expect(bak.existsSync(), isFalse);
  });

  test('资产读取失败时仍返回已解析的真实支持目录路径', () async {
    final resolution = await buildResolver(
      assetBytesLoader: (_) async =>
          throw const FileSystemException('asset load failed'),
    ).resolve();

    expect(resolution.contentPath, '${temp.path}/classical.db');
    expect(resolution.userPath, '${temp.path}/user.db');
    expect(resolution.replaced, isFalse);
    expect(File(resolution.contentPath).existsSync(), isFalse);
  });

  test('DB 已写入但版本文件写失败时仍返回真实路径', () async {
    // 把版本路径占成目录，使首次安装后的版本回写抛错。
    Directory('${temp.path}/db_version.txt').createSync();

    final resolution = await buildResolver().resolve();

    expect(resolution.contentPath, '${temp.path}/classical.db');
    expect(resolution.userPath, '${temp.path}/user.db');
    expect(File(resolution.contentPath).readAsBytesSync(), assetDb);
  });

  test('替换成功后版本回写失败：replaced 仍为 true 且返回真实路径', () async {
    File('${temp.path}/classical.db').writeAsBytesSync(<int>[1, 2]);
    Directory('${temp.path}/db_version.txt').createSync();
    Uint8List? seenTmpBytes;

    final resolution = await buildResolver(
      dbReplace: (newPath, currentPath) {
        seenTmpBytes = File(newPath).readAsBytesSync();
        File(newPath).deleteSync();
        return BridgeError.ok;
      },
    ).resolve();

    expect(resolution.contentPath, '${temp.path}/classical.db');
    expect(resolution.userPath, '${temp.path}/user.db');
    expect(resolution.replaced, isTrue);
    expect(seenTmpBytes, assetDb);
  });

  test('支持目录异常时回退到相对路径且不抛出', () async {
    final resolution = await buildResolver(
      supportDirectoryProvider: () async =>
          throw const FileSystemException('support dir unavailable'),
    ).resolve();

    expect(resolution.contentPath, '../data/classical.db');
    expect(resolution.userPath, '../data/user.db');
    expect(resolution.replaced, isFalse);
  });
}
