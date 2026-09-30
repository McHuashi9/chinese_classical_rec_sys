import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:chinese_classical_rec_sys/engine/announcement.dart';
import 'package:chinese_classical_rec_sys/engine/github_config.dart';
import 'package:chinese_classical_rec_sys/models/version.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/announcement_dialog.dart';

/// 关于卡：版本与数据版本、仓库/更新日志链接、公告、联系方式，以及检查更新。
class AboutSection extends StatefulWidget {
  const AboutSection({super.key});

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    final fontScale = context.select((SettingsController s) => s.fontScale);
    final theme = Theme.of(context);
    final coord = context.read<AppCoordinator>();
    final secondaryColor = context.appColors.inkSecondary;
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: context.cardPaddingH, vertical: context.cardPaddingV),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 20 * fontScale),
                SizedBox(width: context.gapSmall),
                Text('关于', style: theme.textTheme.titleLarge),
              ],
            ),
            SizedBox(height: context.gapSmall),
            Row(
              children: [
                Text('文言文推荐系统',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: secondaryColor)),
                const Spacer(),
                Text('v${AppCoordinator.currentVersion}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: secondaryColor)),
              ],
            ),
            SizedBox(height: context.gapMedium),
            AboutDataRow(
              icon: Icons.storage_outlined,
              label: '内容数据版本',
              value: coord.contentDataVersion,
              color: secondaryColor,
              fontScale: fontScale,
            ),
            SizedBox(height: context.gapSmall),
            AboutDataRow(
              icon: Icons.dataset_outlined,
              label: '数据库格式版本',
              value: coord.schemaVersions == null
                  ? '不可用'
                  : '内容 ${coord.schemaVersions!.$2} · 用户 ${coord.schemaVersions!.$1}',
              color: secondaryColor,
              fontScale: fontScale,
            ),
            SizedBox(height: context.gapMedium),
            Divider(color: context.appColors.border, height: 1),
            SizedBox(height: context.gapMedium),
            _AboutLinkRow(
              icon: Icons.code,
              label: 'GitHub 仓库',
              url: GithubConfig.repoUrl,
              fontScale: fontScale,
              color: secondaryColor,
            ),
            SizedBox(height: context.gapSmall),
            _AboutLinkRow(
              icon: Icons.update,
              label: '更新日志',
              url: GithubConfig.releasesUrl,
              fontScale: fontScale,
              color: secondaryColor,
            ),
            SizedBox(height: context.gapSmall),
            InkWell(
              onTap: () async {
                final announcement = await loadCurrentAnnouncement();
                final prefs = await SharedPreferences.getInstance();
                if (!context.mounted) return;
                if (announcement == null) {
                  // 公告 asset 缺失/坏格式：明确告知，而不是弹出空对话框
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('公告不可用，请稍后重试')),
                  );
                  return;
                }
                await AnnouncementDialog.show(
                  context,
                  announcement: announcement,
                  initialMode: loadAnnouncementMode(prefs),
                  onModeChanged: (m) async {
                    await saveAnnouncementMode(prefs, m);
                  },
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.campaign_outlined,
                        size: 16 * fontScale, color: secondaryColor),
                    SizedBox(width: context.gapSmall),
                    Text('公告 / 作者的话',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: secondaryColor)),
                  ],
                ),
              ),
            ),
            SizedBox(height: context.gapMedium),
            Row(
              children: [
                Icon(Icons.mail_outline,
                    size: 16 * fontScale, color: secondaryColor),
                SizedBox(width: context.gapSmall),
                Expanded(
                  child: Text('mc_huashi9@163.com',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: secondaryColor)),
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(
                        const ClipboardData(text: 'mc_huashi9@163.com'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('邮箱已复制'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4 * fontScale),
                    child: Icon(Icons.copy,
                        size: 16 * fontScale, color: secondaryColor),
                  ),
                ),
              ],
            ),
            SizedBox(height: context.gapMedium),
            Row(
              children: [
                Icon(Icons.article,
                    size: 16 * fontScale, color: secondaryColor),
                SizedBox(width: context.gapSmall),
                Text('MIT License',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: secondaryColor)),
              ],
            ),
            SizedBox(height: context.gapMedium),
            Divider(color: context.appColors.border, height: 1),
            SizedBox(height: context.gapMedium),
            _buildCheckUpdateButton(context, fontScale),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckUpdateButton(BuildContext context, double fontScale) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _checking ? null : () => _checkForUpdates(context),
        icon: _checking
            ? SizedBox(
                width: 16 * fontScale,
                height: 16 * fontScale,
                child: CircularProgressIndicator(strokeWidth: 2 * fontScale),
              )
            : Icon(Icons.system_update, size: 18 * fontScale),
        label: Text(_checking ? '检查中...' : '检查更新'),
      ),
    );
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    if (_checking) return;
    setState(() => _checking = true);

    final settingsCtrl = context.read<SettingsController>();
    final messenger = ScaffoldMessenger.of(context);
    final current = Version.parse(AppCoordinator.currentVersion);

    try {
      final latest = await settingsCtrl
          .manualCheckForUpdates(AppCoordinator.currentVersion);

      if (!mounted) return;

      if (latest == null) {
        final reason = settingsCtrl.updateCheckError ?? '网络不可用，请稍后重试';
        messenger.showSnackBar(SnackBar(content: Text(reason)));
      } else if (latest == current) {
        messenger.showSnackBar(
          const SnackBar(
              content: Text('已是最新版本 ${AppCoordinator.currentVersion}')),
        );
      } else if (latest > current) {
        await _showUpdateDialog(latest.toString());
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _showUpdateDialog(String latestVersion) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 v$latestVersion'),
        content: const Text('当前版本: ${AppCoordinator.currentVersion}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () {
              _launch(
                ctx,
                GithubConfig.releaseTagUrl(latestVersion),
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('前往下载'),
          ),
        ],
      ),
    );
  }
}

void _launch(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await launchUrl(Uri.parse(url));
  } catch (_) {
    try {
      messenger.showSnackBar(
        SnackBar(content: Text('无法打开浏览器，请手动访问: $url')),
      );
    } catch (_) {}
  }
}

class AboutDataRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final double fontScale;

  const AboutDataRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.fontScale,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16 * fontScale, color: color),
        SizedBox(width: context.gapSmall),
        Text(label,
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _AboutLinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;
  final double fontScale;
  final Color color;

  const _AboutLinkRow({
    required this.icon,
    required this.label,
    required this.url,
    required this.fontScale,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _launch(context, url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 16 * fontScale, color: color),
            SizedBox(width: context.gapSmall),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
