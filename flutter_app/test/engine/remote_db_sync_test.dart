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

    test('版本相同则跳过下载，返回 false', () async {
      await writeVer('20260101-abc');
      final sync = RemoteDbSync(prefs, tmpDir.path,
          client: MockClient((_) async => http.Response('', 500)));
      final result = await sync.trySyncFromRelease(
        remoteVersion: '20260101-abc',
        downloadUrl: 'http://x/classical.db',
      );
      expect(result, false);
    });

    test('gzip 数据包正确解压落库，并写回新版本号', () async {
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
      expect(result, true);
      final saved = await File('${tmpDir.path}/classical.db').readAsBytes();
      expect(utf8.decode(saved), 'mock-sqlite-content');
      final ver = await File('${tmpDir.path}/db_version.txt').readAsString();
      expect(ver.trim(), '20260608-1c84aab');
    });
  });
}