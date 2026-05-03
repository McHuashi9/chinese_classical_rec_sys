import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
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
    final logLevel = context.select((AppState a) => a.logLevel);

    return SingleChildScrollView(
          padding: EdgeInsets.all(context.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('设置', style: Theme.of(context).textTheme.headlineLarge),
              SizedBox(height: context.gapHuge),
              const Divider(color: AppTheme.border, height: 1),
              SizedBox(height: context.gapXHuge),
              _buildAppearanceCard(context, isDark),
              SizedBox(height: context.gapHuge),
              _buildLoggingCard(context, isDark, logLevel),
              SizedBox(height: context.gapHuge),
              _buildAboutCard(isDark),
            ],
          ),
    );
  }

  Widget _buildAppearanceCard(BuildContext context, bool isDark) {
    final app = context.read<AppState>();
    final isSmall = MediaQuery.sizeOf(context).width < 480;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(context.cardPaddingH),
        child: isSmall
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '外观',
                    style: TextStyle(
                      fontSize: 20,
                      fontFamily: AppTheme.fontTitle,
                      color: isDark ? AppTheme.darkInk : AppTheme.ink,
                    ),
                  ),
                  SizedBox(height: context.gapMedium),
                  Text(
                    '主题',
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: AppTheme.fontUI,
                      color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                    ),
                  ),
                  SizedBox(height: context.gapSmall),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(value: 'light', label: Text('亮色')),
                      ButtonSegment<String>(value: 'dark', label: Text('暗色')),
                    ],
                    selected: {isDark ? 'dark' : 'light'},
                    onSelectionChanged: (Set<String> selection) {
                      app.setDarkMode(selection.first == 'dark');
                    },
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: WidgetStateProperty.all(
                        const TextStyle(fontSize: 14, fontFamily: AppTheme.fontUI),
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Text(
                    '外观',
                    style: TextStyle(
                      fontSize: 20,
                      fontFamily: AppTheme.fontTitle,
                      color: isDark ? AppTheme.darkInk : AppTheme.ink,
                    ),
                  ),
                  SizedBox(width: context.gapXHuge),
                  Text(
                    '主题',
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: AppTheme.fontUI,
                      color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                    ),
                  ),
                  const Spacer(),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(value: 'light', label: Text('亮色')),
                      ButtonSegment<String>(value: 'dark', label: Text('暗色')),
                    ],
                    selected: {isDark ? 'dark' : 'light'},
                    onSelectionChanged: (Set<String> selection) {
                      app.setDarkMode(selection.first == 'dark');
                    },
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: WidgetStateProperty.all(
                        const TextStyle(fontSize: 14, fontFamily: AppTheme.fontUI),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildLoggingCard(BuildContext context, bool isDark, String logLevel) {
    final isSmall = MediaQuery.sizeOf(context).width < 480;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(context.cardPaddingH),
        child: isSmall
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '日志',
                    style: TextStyle(
                      fontSize: 20,
                      fontFamily: AppTheme.fontTitle,
                      color: isDark ? AppTheme.darkInk : AppTheme.ink,
                    ),
                  ),
                  SizedBox(height: context.gapMedium),
                  Text(
                    '日志级别',
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: AppTheme.fontUI,
                      color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                    ),
                  ),
                  SizedBox(height: context.gapSmall),
                  SizedBox(
                    width: 150,
                    child: DropdownButtonFormField<String>(
                      initialValue: logLevel,
                      items: ['INFO', 'DEBUG', 'WARN', 'ERROR']
                          .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) context.read<AppState>().setLogLevel(v);
                      },
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Text(
                    '日志',
                    style: TextStyle(
                      fontSize: 20,
                      fontFamily: AppTheme.fontTitle,
                      color: isDark ? AppTheme.darkInk : AppTheme.ink,
                    ),
                  ),
                  SizedBox(width: context.gapXHuge),
                  Text(
                    '日志级别',
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: AppTheme.fontUI,
                      color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 150,
                    child: DropdownButtonFormField<String>(
                      initialValue: logLevel,
                      items: ['INFO', 'DEBUG', 'WARN', 'ERROR']
                          .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) context.read<AppState>().setLogLevel(v);
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildAboutCard(bool isDark) {
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: context.cardPaddingH,
            vertical: context.cardPaddingV),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '关于',
              style: TextStyle(
                fontSize: 20,
                fontFamily: AppTheme.fontTitle,
                color: isDark ? AppTheme.darkInk : AppTheme.ink,
              ),
            ),
            SizedBox(height: context.gapSmall),
            Text(
              '古典文学阅读推荐系统',
              style: TextStyle(
                fontSize: 16,
                fontFamily: AppTheme.fontUI,
                color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
              ),
            ),
            SizedBox(height: context.gapTiny),
            Text(
              '版本 ${AppState.currentVersion}',
              style: TextStyle(
                fontSize: 14,
                fontFamily: AppTheme.fontUI,
                color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
              ),
            ),
            SizedBox(height: context.cardPaddingV),
            _buildCheckUpdateButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckUpdateButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _checking ? null : () => _checkForUpdates(context),
        icon: _checking
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.system_update, size: 18),
        label: Text(_checking ? '检查中...' : '检查更新'),
      ),
    );
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    if (_checking) return;
    setState(() => _checking = true);

    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final latest = await app.manualCheckForUpdates();

      if (!mounted) return;

      if (latest == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('网络不可用，请稍后重试')),
        );
      } else if (latest.toString() == AppState.currentVersion) {
        messenger.showSnackBar(
          // ignore: prefer_const_constructors
          SnackBar(content: Text('已是最新版本 ${AppState.currentVersion}')),
        );
      } else {
        // ignore: use_build_context_synchronously
        await _showUpdateDialog(context, latest.toString());
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _showUpdateDialog(BuildContext context, String latestVersion) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 v$latestVersion'),
        // ignore: prefer_const_constructors
        content: Text('当前版本: ${AppState.currentVersion}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () {
              launchUrl(Uri.parse(
                'https://github.com/anomalyco/chinese_classical_rec_sys/releases/tag/v$latestVersion',
              ));
              Navigator.of(ctx).pop();
            },
            child: const Text('前往下载'),
          ),
        ],
      ),
    );
  }
}
