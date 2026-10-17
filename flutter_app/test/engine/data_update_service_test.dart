import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chinese_classical_rec_sys/engine/data_update_service.dart';
import 'package:chinese_classical_rec_sys/engine/github_config.dart';

void main() {
  final fixedNow = DateTime.fromMillisecondsSinceEpoch(1780000000000);
  late Directory temp;
  late SharedPreferences prefs;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('data_update_service_test_');
    File('${temp.path}/db_version.txt').writeAsStringSync('202601010000-0a0');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  DataUpdateService buildService(
    MockClient client, {
    RemoteDataSyncRunner? syncRunner,
    Future<String> Function()? localVersionReader,
  }) {
    return DataUpdateService(
      prefs: prefs,
      dbDirPath: temp.path,
      syncRunner: syncRunner ?? (_, __) async {},
      client: client,
      now: () => fixedNow,
      localVersionReader: localVersionReader,
    );
  }

  String releaseBody({
    String dbUrl = 'https://example.com/classical.db.gz',
    String verUrl = 'https://example.com/db_version.txt',
    bool includeAssets = true,
  }) {
    return jsonEncode(<Map<String, dynamic>>[
      <String, dynamic>{
        'assets': includeAssets
            ? <Map<String, dynamic>>[
                <String, dynamic>{
                  'name': 'classical.db.gz',
                  'browser_download_url': dbUrl,
                },
                <String, dynamic>{
                  'name': 'db_version.txt',
                  'browser_download_url': verUrl,
                },
              ]
            : <Map<String, dynamic>>[],
      },
    ]);
  }

  MockClient releaseClient({
    required String versionBody,
    int verStatus = 200,
    void Function()? onVersionRequest,
  }) {
    return MockClient((request) async {
      if (request.url.toString() == GithubConfig.releaseApiList) {
        return http.Response(releaseBody(), 200);
      }
      if (request.url.toString() == 'https://example.com/db_version.txt') {
        onVersionRequest?.call();
        return http.Response(versionBody, verStatus);
      }
      return http.Response('not found', 404);
    });
  }

  test('冷却窗口内不发起网络请求', () async {
    await prefs.setInt(
      kDbCheckLastMsKey,
      fixedNow.millisecondsSinceEpoch - const Duration(hours: 1).inMilliseconds,
    );
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response(releaseBody(), 200);
    });

    final asset = await buildService(client).fetchLatestAsset();

    expect(asset, isNull);
    expect(requests, 0);
  });

  test('时钟回拨不阻塞检查', () async {
    await prefs.setInt(
      kDbCheckLastMsKey,
      fixedNow.millisecondsSinceEpoch + const Duration(hours: 1).inMilliseconds,
    );
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      if (request.url.toString() == GithubConfig.releaseApiList) {
        return http.Response(releaseBody(), 200);
      }
      return http.Response('202608101200-abc', 200);
    });

    final asset = await buildService(client).fetchLatestAsset();

    expect(requests, 2);
    expect(asset, isNotNull);
    expect(asset!.version, '202608101200-abc');
  });

  test('release 列表 HTTP 失败不写冷却', () async {
    final client = MockClient((_) async => http.Response('err', 500));

    final asset = await buildService(client).fetchLatestAsset();

    expect(asset, isNull);
    expect(prefs.getInt(kDbCheckLastMsKey), isNull);
  });

  test('release 缺数据资产不写冷却', () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode(<dynamic>[
            <String, dynamic>{'assets': <dynamic>[]},
          ]),
          200,
        ));

    final asset = await buildService(client).fetchLatestAsset();

    expect(asset, isNull);
    expect(prefs.getInt(kDbCheckLastMsKey), isNull);
  });

  test('db_version.txt 下载失败不写冷却', () async {
    final client = releaseClient(versionBody: 'err', verStatus: 500);

    final asset = await buildService(client).fetchLatestAsset();

    expect(asset, isNull);
    expect(prefs.getInt(kDbCheckLastMsKey), isNull);
  });

  test('远端版本不新：写冷却并返回 null', () async {
    final client = releaseClient(versionBody: '202601010000-0a0');

    final asset = await buildService(client).fetchLatestAsset();

    expect(asset, isNull);
    expect(prefs.getInt(kDbCheckLastMsKey), fixedNow.millisecondsSinceEpoch);
  });

  test('发现新数据卷：返回下载信息，暂不写冷却', () async {
    final client = releaseClient(versionBody: '202608101200-abc');

    final asset = await buildService(client).fetchLatestAsset();

    expect(asset, isNotNull);
    expect(asset!.version, '202608101200-abc');
    expect(asset.downloadUrl, 'https://example.com/classical.db.gz');
    expect(prefs.getInt(kDbCheckLastMsKey), isNull);
  });

  test('本地版本读取失败按 unknown 处理', () async {
    final client = releaseClient(versionBody: '202608101200-abc');
    final service = buildService(
      client,
      localVersionReader: () async => throw const FileSystemException('boom'),
    );

    final asset = await service.fetchLatestAsset();

    expect(asset, isNotNull);
    expect(await service.readLocalDbVersion(), 'unknown');
  });

  test('runSilentSync 捕获同步异常且不外抛', () async {
    final client = releaseClient(versionBody: '202608101200-abc');
    var syncCalled = false;
    final service = buildService(
      client,
      syncRunner: (remoteVersion, downloadUrl) async {
        syncCalled = true;
        expect(remoteVersion, '202608101200-abc');
        expect(downloadUrl, 'https://example.com/classical.db.gz');
        throw StateError('network failed');
      },
    );

    await expectLater(service.runSilentSync(), completes);
    expect(syncCalled, isTrue);
  });
}
