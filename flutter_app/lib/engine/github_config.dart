class GithubConfig {
  static const repoOwner = 'McHuashi9';
  static const repoName = 'chinese_classical_rec_sys';

  static String get repoUrl =>
      'https://github.com/$repoOwner/$repoName';

  static String get releaseApiLatest =>
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  static String releaseApiByVersion(String version) =>
      'https://api.github.com/repos/$repoOwner/$repoName/releases/tags/v$version';

  static String releaseTagUrl(String version) =>
      '$repoUrl/releases/tag/v$version';
}
