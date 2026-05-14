import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
import 'package:chinese_classical_rec_sys/models/version.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    final isDark = context.select((AppState a) => a.darkMode);
    final fontScale = context.select((AppState a) => a.fontScale);
    final logLevel = context.select((AppState a) => a.logLevel);
    final isSmall = MediaQuery.sizeOf(context).width < 480;

    return SingleChildScrollView(
      padding: EdgeInsets.all(context.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设置', style: Theme.of(context).textTheme.headlineLarge),
          SizedBox(height: context.gapHuge),
          const Divider(color: AppTheme.border, height: 1),
          SizedBox(height: context.gapXHuge),
          _buildAppearanceCard(context, isDark, fontScale),
          SizedBox(height: context.gapHuge),
          _buildLoggingCard(context, isSmall, logLevel, fontScale),
          SizedBox(height: context.gapHuge),
          _buildAboutCard(isDark, fontScale),
        ],
      ),
    );
  }

  Widget _buildAppearanceCard(
      BuildContext context, bool isDark, double fontScale) {
    final app = context.read<AppState>();
    return Card(
      child: Padding(
        padding: EdgeInsets.all(context.cardPaddingH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.palette_outlined, size: 20 * fontScale),
                SizedBox(width: context.gapSmall),
                Text('外观', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            SizedBox(height: context.gapSmall),
            SwitchListTile(
              title: const Text('暗色模式'),
              secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
              value: isDark,
              onChanged: (v) => app.setDarkMode(v),
              contentPadding: EdgeInsets.zero,
            ),
            SizedBox(height: context.gapMedium),
            const _FontScaleSelector(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggingCard(
      BuildContext context, bool isSmall, String logLevel, double fontScale) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(context.cardPaddingH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bug_report_outlined, size: 20 * fontScale),
                SizedBox(width: context.gapSmall),
                Text('日志', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            SizedBox(height: context.gapSmall),
            Row(
              children: [
                Text('日志级别',
                    style: Theme.of(context).textTheme.labelLarge),
                SizedBox(width: isSmall ? context.gapXHuge : 0),
                if (!isSmall) const Spacer(),
                SizedBox(
                  width: isSmall ? 150.0 : 220.0,
                  child: DropdownButtonFormField<String>(
                    value: logLevel,
                    items: ['INFO', 'DEBUG', 'WARN', 'ERROR']
                        .map((l) =>
                            DropdownMenuItem(value: l, child: Text(l)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        context.read<AppState>().setLogLevel(v);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutCard(bool isDark, double fontScale) {
    final theme = Theme.of(context);
    final secondaryColor =
        isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary;
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: context.cardPaddingH,
            vertical: context.cardPaddingV),
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
                Text('古典文学阅读推荐系统',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: secondaryColor)),
                const Spacer(),
                Text('v${AppState.currentVersion}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: secondaryColor)),
              ],
            ),
            SizedBox(height: context.gapMedium),
            const Divider(color: AppTheme.border, height: 1),
            SizedBox(height: context.gapMedium),
            _AboutLinkRow(
              icon: Icons.code,
              label: 'GitHub 仓库',
              url: 'https://github.com/McHuashi9/chinese_classical_rec_sys',
              fontScale: fontScale,
              color: secondaryColor,
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
            const Divider(color: AppTheme.border, height: 1),
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
                child:
                    CircularProgressIndicator(strokeWidth: 2 * fontScale),
              )
            : Icon(Icons.system_update, size: 18 * fontScale),
        label: Text(_checking ? '检查中...' : '检查更新'),
      ),
    );
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    if (_checking) return;
    setState(() => _checking = true);

    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final current = Version.parse(AppState.currentVersion);

    try {
      final latest = await app.manualCheckForUpdates();

      if (!mounted) return;

      if (latest == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('网络不可用，请稍后重试')),
        );
      } else if (latest == current) {
        messenger.showSnackBar(
          SnackBar(content: Text('已是最新版本 ${AppState.currentVersion}')),
        );
      } else if (latest > current) {
        await _showUpdateDialog(context, latest.toString());
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _showUpdateDialog(
      BuildContext context, String latestVersion) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 v$latestVersion'),
        content: Text('当前版本: ${AppState.currentVersion}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () {
              _launch(
                ctx,
                'https://github.com/McHuashi9/chinese_classical_rec_sys/releases/tag/v$latestVersion',
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
  try {
    await launchUrl(Uri.parse(url));
  } catch (_) {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开浏览器，请手动访问: $url')),
      );
    } catch (_) {}
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
        padding: EdgeInsets.symmetric(vertical: 2),
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

class _FontScaleSelector extends StatelessWidget {
  const _FontScaleSelector();

  static const _values = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5];
  static const _labels = [
    '0.75x', '1.0x', '1.25x', '1.5x', '1.75x', '2.0x', '2.25x', '2.5x',
  ];

  @override
  Widget build(BuildContext context) {
    final fontScale = context.select((AppState a) => a.fontScale);
    final app = context.read<AppState>();
    final isSmall = MediaQuery.sizeOf(context).width < 480;

    if (isSmall) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('字号', style: Theme.of(context).textTheme.labelLarge),
          SizedBox(height: context.gapSmall),
          DropdownButton<double>(
            value: fontScale,
            items: [
              for (var i = 0; i < _values.length; i++)
                DropdownMenuItem(value: _values[i], child: Text(_labels[i])),
            ],
            onChanged: (v) {
              if (v != null) app.setFontScale(v);
            },
          ),
        ],
      );
    }
    return Row(
      children: [
        Text('字号', style: Theme.of(context).textTheme.labelLarge),
        const Spacer(),
        SegmentedButton<double>(
          segments: [
            for (var i = 0; i < _values.length; i++)
              ButtonSegment(value: _values[i], label: Text(_labels[i])),
          ],
          selected: {fontScale},
          onSelectionChanged: (Set<double> selection) {
            app.setFontScale(selection.first);
          },
          style: ButtonStyle(
            textStyle: WidgetStateProperty.all(
              Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }
}
