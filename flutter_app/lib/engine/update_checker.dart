import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/models/version.dart';
import 'package:chinese_classical_rec_sys/engine/app_logger.dart';

class UpdateChecker {
  static const _releaseUrl =
      'https://api.github.com/repos/anomalyco/chinese_classical_rec_sys/releases/latest';
  static const _autoCheckInterval = Duration(hours: 24);
  static const _minManualInterval = Duration(minutes: 5);
  static const _rateLimitBackoff = Duration(hours: 1);

  final SharedPreferences _prefs;
  String? _token;

  UpdateChecker(this._prefs);

  void setToken(String? token) {
    _token = token;
  }

  Future<Version?> checkSilently(String currentVersion) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastCheck = _prefs.getInt('update_last_check_ms') ?? 0;
    if (now - lastCheck < _autoCheckInterval.inMilliseconds) {
      return null;
    }
    return _check(currentVersion);
  }

  Future<Version?> checkManually(String currentVersion) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastManual = _prefs.getInt('update_last_manual_ms') ?? 0;
    if (now - lastManual < _minManualInterval.inMilliseconds) {
      return null; // 间隔不足，调用方自行提示
    }

    final rateLimited = _prefs.getInt('update_rate_limited_until_ms') ?? 0;
    if (now < rateLimited) {
      return null; // 仍在退避期
    }

    await _prefs.setInt('update_last_manual_ms', now);
    final result = await _fetchLatestVersion();
    if (result != null) {
      await _prefs.setInt('update_last_check_ms', now);
    }
    if (result == null) return null;
    return result.toVersion() > Version.parse(currentVersion) ? result.toVersion() : null;
  }

  Future<Version?> _check(String currentVersion) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    final rateLimited = _prefs.getInt('update_rate_limited_until_ms') ?? 0;
    if (now < rateLimited) return null;

    final result = await _fetchLatestVersion();
    if (result != null) {
      await _prefs.setInt('update_last_check_ms', now);
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

      final etag = _prefs.getString('update_etag');
      if (etag != null) {
        headers['If-None-Match'] = etag;
      }

      final resp = await http.get(Uri.parse(_releaseUrl), headers: headers);

      final remaining = int.tryParse(resp.headers['x-ratelimit-remaining'] ?? '') ?? 60;
      if (remaining <= 5) {
        final until = DateTime.now().millisecondsSinceEpoch + _rateLimitBackoff.inMilliseconds;
        await _prefs.setInt('update_rate_limited_until_ms', until);
        AppLogger().warn('rate limit 即将耗尽 ($remaining)，退避 1 小时');
        return null;
      }

      if (resp.statusCode == 304) return null; // ETag 未变化
      if (resp.statusCode == 403) {
        final until = DateTime.now().millisecondsSinceEpoch + _rateLimitBackoff.inMilliseconds;
        await _prefs.setInt('update_rate_limited_until_ms', until);
        AppLogger().warn('403 限流/滥用，退避 1 小时');
        return null;
      }
      if (resp.statusCode != 200) return null;

      final newEtag = resp.headers['etag'];
      if (newEtag != null) {
        await _prefs.setString('update_etag', newEtag);
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = json['tag_name'] as String?;
      if (tag == null) return null;

      return _ReleaseResult(tagName: tag);
    } catch (e) {
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
