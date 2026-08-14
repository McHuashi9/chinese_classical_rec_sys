class GithubConfig {
  static const repoOwner = 'McHuashi9';
  static const repoName = 'chinese_classical_rec_sys';

  static String get repoUrl =>
      'https://github.com/$repoOwner/$repoName';

  static String get releaseApiLatest =>
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  static String get releaseApiList =>
      'https://api.github.com/repos/$repoOwner/$repoName/releases?per_page=100';

  static String releaseTagUrl(String version) =>
      '$repoUrl/releases/tag/v$version';
}
