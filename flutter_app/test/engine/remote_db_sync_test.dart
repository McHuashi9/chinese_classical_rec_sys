import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/engine/remote_db_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RemoteDbSync', () {
    late Directory tmpDir;
    late SharedPreferences prefs;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('rds_test');
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    tearDown(() async {
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });

    Future<void> writeVer(String ver) async {
      await File('${tmpDir.path}/db_version.txt').writeAsString(ver);
    }

    test('版本相同则跳过下载，返回 null', () async {
      await writeVer('20260101-abc');
      final sync = RemoteDbSync(prefs, tmpDir.path,
          client: MockClient((_) async => http.Response('', 500)));
      final result = await sync.trySyncFromRelease(
        remoteVersion: '20260101-abc',
        downloadUrl: 'http://x/classical.db',
      );
      expect(result, null);
    });

    test('远端比本地旧则跳过下载（方向判断，绝不降级）', () async {
      await writeVer('20260701-abc'); // 本地较新
      final sync = RemoteDbSync(prefs, tmpDir.path,
          client: MockClient((_) async => http.Response('', 500)));
      final result = await sync.trySyncFromRelease(
        remoteVersion: '20260601-abc',
        downloadUrl: 'http://x/classical.db',
      );
      expect(result, null);
      expect(File('${tmpDir.path}/classical.db.tmp').existsSync(), false);
    });

    test('本地版本无法解析时视为最旧，允许下载', () async {
      await writeVer('garbage-not-a-version');
      final sync = RemoteDbSync(prefs, tmpDir.path,
          client: MockClient((_) async => http.Response.bytes([], 200)));
      final result = await sync.trySyncFromRelease(
        remoteVersion: '20260608-1c84aab',
        downloadUrl: 'http://x/classical.db',
      );
      expect(result, isNotNull);
    });

    test('24h 同步冷却期内跳过', () async {
      await writeVer('old-version');
      await prefs.setInt('db_last_sync_ms', DateTime.now().millisecondsSinceEpoch);
      final sync = RemoteDbSync(prefs, tmpDir.path,
          client: MockClient((_) async => http.Response('', 500)));
      final result = await sync.trySyncFromRelease(
        remoteVersion: '20260608-1c84aab',
        downloadUrl: 'http://x/classical.db',
      );
      expect(result, null);
    });

    test('gzip 数据包正确解压为 tmp 文件，返回其路径', () async {
      await writeVer('old-version');
      final dbBytes = utf8.encode('mock-sqlite-content');
      final gz = gzip.encode(dbBytes);
      final client = MockClient((req) async {
        expect(req.url.path, '/api/classical.db.gz');
        return http.Response.bytes(gz, 200);
      });
      final sync = RemoteDbSync(prefs, tmpDir.path, client: client);
      final result = await sync.trySyncFromRelease(
        remoteVersion: '20260608-1c84aab',
        downloadUrl: 'http://example.com/api/classical.db.gz',
      );
      expect(result, '${tmpDir.path}/classical.db.tmp');
      final saved = await File(result!).readAsBytes();
      expect(utf8.decode(saved), 'mock-sqlite-content');
    });

    test('markSynced 写入同步时间标记', () async {
      final sync = RemoteDbSync(prefs, tmpDir.path,
          client: MockClient((_) async => http.Response('', 500)));
      await sync.markSynced();
      expect(prefs.getInt('db_last_sync_ms'), isNotNull);
    });

    test('commitVersion 把远端版本回写到 db_version.txt', () async {
      await writeVer('old-version');
      final sync = RemoteDbSync(prefs, tmpDir.path,
          client: MockClient((_) async => http.Response('', 500)));
      await sync.commitVersion('202608071530-abcd123');
      final ver = await File('${tmpDir.path}/db_version.txt').readAsString();
      expect(ver.trim(), '202608071530-abcd123');
    });

    test('commitVersion 重写后可被后续方向判断正确识别为最新', () async {
      await writeVer('20260608-1c84aab');
      final sync = RemoteDbSync(prefs, tmpDir.path,
          client: MockClient((_) async => http.Response('', 500)));
      await sync.commitVersion('202608071530-abcd123');
      // 冷却期外，同版本应视为最新并跳过下载
      final later = RemoteDbSync(prefs, tmpDir.path,
          client: MockClient((_) async => http.Response('', 500)));
      final result = await later.trySyncFromRelease(
        remoteVersion: '202608071530-abcd123',
        downloadUrl: 'http://x/classical.db',
      );
      expect(result, null);
    });
  });
}