import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/models/version.dart';
import 'package:chinese_classical_rec_sys/engine/app_logger.dart';
import 'package:chinese_classical_rec_sys/engine/github_config.dart';

class UpdateChecker {
  static final _releaseUrl = GithubConfig.releaseApiLatest;
  static const _autoCheckInterval = Duration(hours: 24);
  static const _minManualInterval = Duration(minutes: 5);
  static const _rateLimitBackoff = Duration(hours: 1);

  /// SharedPreferences 键（单测复用同名常量，避免魔法字符串漂移）
  static const prefKeyLastCheck = 'update_last_check_ms';
  static const prefKeyLastManual = 'update_last_manual_ms';
  static const prefKeyRateLimitedUntil = 'update_rate_limited_until_ms';
  static const prefKeyEtag = 'update_etag';
  static const prefKeyTagName = 'update_tag_name';

  final SharedPreferences _prefs;
  final http.Client _client;
  String? _token;

  /// 上次手动检查失败的原因，null 表示未失败或尚未检查
  String? lastErrorReason;

  UpdateChecker(this._prefs, {http.Client? client})
      : _client = client ?? http.Client();

  void setToken(String? token) {
    _token = token;
  }

  Future<Version?> checkSilently(String currentVersion) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastCheck = _prefs.getInt(prefKeyLastCheck) ?? 0;
    if (now - lastCheck < _autoCheckInterval.inMilliseconds) {
      return null;
    }
    return _check(currentVersion);
  }

  Future<Version?> checkManually(String currentVersion) async {
    lastErrorReason = null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastManual = _prefs.getInt(prefKeyLastManual) ?? 0;
    if (now - lastManual < _minManualInterval.inMilliseconds) {
      lastErrorReason = '操作太频繁，请稍后再试';
      return null;
    }

    final rateLimited = _prefs.getInt(prefKeyRateLimitedUntil) ?? 0;
    if (now < rateLimited) {
      lastErrorReason = '请求已被限流，请一小时后重试';
      return null;
    }

    await _prefs.setInt(prefKeyLastManual, now);
    final result = await _fetchLatestVersion();
    if (result == null) return null;
    await _prefs.setInt(prefKeyLastCheck, now);
    return result.toVersion();
  }

  Future<Version?> _check(String currentVersion) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    final rateLimited = _prefs.getInt(prefKeyRateLimitedUntil) ?? 0;
    if (now < rateLimited) return null;

    final result = await _fetchLatestVersion();
    if (result != null) {
      await _prefs.setInt(prefKeyLastCheck, now);
      if (result.toVersion() > Version.parse(currentVersion)) {
        return result.toVersion();
      }
    }
    return null;
  }

  Future<_ReleaseResult?> _fetchLatestVersion() async {
    try {
      final headers = <String, String>{
        'Accept': 'application/vnd.github.v3+json',
      };
      if (_token != null && _token!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_token';
      }

      final etag = _prefs.getString(prefKeyEtag);
      if (etag != null) {
        headers['If-None-Match'] = etag;
      }

      final resp = await _client.get(Uri.parse(_releaseUrl), headers: headers);

      final remaining = int.tryParse(resp.headers['x-ratelimit-remaining'] ?? '') ?? 60;
      if (remaining <= 5) {
        final until = DateTime.now().millisecondsSinceEpoch + _rateLimitBackoff.inMilliseconds;
        await _prefs.setInt(prefKeyRateLimitedUntil, until);
        lastErrorReason = 'API 请求次数已达上限，请一小时后重试';
        AppLogger().warn('rate limit 即将耗尽 ($remaining)，退避 1 小时');
        return null;
      }

      if (resp.statusCode == 304) {
        // ETag 未变化，返回缓存版本
        final cachedTag = _prefs.getString(prefKeyTagName);
        if (cachedTag != null) return _ReleaseResult(tagName: cachedTag);
        lastErrorReason = '服务器返回未修改，但本地无缓存版本';
        return null;
      }
      if (resp.statusCode == 403) {
        final until = DateTime.now().millisecondsSinceEpoch + _rateLimitBackoff.inMilliseconds;
        await _prefs.setInt(prefKeyRateLimitedUntil, until);
        lastErrorReason = 'API 请求被限流，请一小时后重试';
        AppLogger().warn('403 限流/滥用，退避 1 小时');
        return null;
      }
      if (resp.statusCode != 200) {
        lastErrorReason = '服务器返回异常 (HTTP ${resp.statusCode})';
        return null;
      }

      final newEtag = resp.headers['etag'];
      if (newEtag != null) {
        await _prefs.setString(prefKeyEtag, newEtag);
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = json['tag_name'] as String?;
      if (tag == null) return null;

      await _prefs.setString(prefKeyTagName, tag);
      return _ReleaseResult(tagName: tag);
    } catch (e) {
      lastErrorReason = '网络不可用，请检查连接后重试';
      AppLogger().error('请求失败: $e');
      return null;
    }
  }
}

class _ReleaseResult {
  final String tagName;
  const _ReleaseResult({required this.tagName});

  Version toVersion() => Version.parse(tagName);
}
