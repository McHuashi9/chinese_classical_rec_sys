import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/github_config.dart';

void main() {
  group('GithubConfig', () {
    test('repoUrl 指向仓库主页', () {
      expect(
        GithubConfig.repoUrl,
        'https://github.com/McHuashi9/chinese_classical_rec_sys',
      );
    });

    test('releaseApiLatest 指向 latest release API', () {
      expect(
        GithubConfig.releaseApiLatest,
        'https://api.github.com/repos/McHuashi9/chinese_classical_rec_sys'
        '/releases/latest',
      );
    });

    test('releaseApiList 每页 100 条', () {
      expect(
        GithubConfig.releaseApiList,
        'https://api.github.com/repos/McHuashi9/chinese_classical_rec_sys'
        '/releases?per_page=100',
      );
    });

    test('releaseTagUrl 生成带 v 前缀的 tag 链接', () {
      expect(
        GithubConfig.releaseTagUrl('1.2.3'),
        'https://github.com/McHuashi9/chinese_classical_rec_sys'
        '/releases/tag/v1.2.3',
      );
    });

    test('releaseTagUrl 保留版本号原样', () {
      expect(
        GithubConfig.releaseTagUrl('data-20260811-abc'),
        'https://github.com/McHuashi9/chinese_classical_rec_sys'
        '/releases/tag/vdata-20260811-abc',
      );
    });
  });
}
