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
    final fontScale = context.select((AppState a) => a.fontScale);
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
              _buildAppearanceCard(context, isDark, fontScale),
              SizedBox(height: context.gapHuge),
              _buildLoggingCard(context, isDark, logLevel),
              SizedBox(height: context.gapHuge),
              _buildAboutCard(isDark),
            ],
          ),
    );
  }

  Widget _buildAppearanceCard(BuildContext context, bool isDark, double fontScale) {
    final app = context.read<AppState>();
    final isSmall = MediaQuery.sizeOf(context).width < 480;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(context.cardPaddingH),
        child: isSmall
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('外观', style: Theme.of(context).textTheme.titleLarge),
                  SizedBox(height: context.gapMedium),
                  Text('主题', style: Theme.of(context).textTheme.labelLarge),
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
                        Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                  SizedBox(height: context.gapMedium),
                  Text('字号', style: Theme.of(context).textTheme.labelLarge),
                  SizedBox(height: context.gapSmall),
                  if (isSmall)
                    DropdownButton<double>(
                      value: fontScale,
                      items: const [
                        DropdownMenuItem(value: 0.75, child: Text('小 (0.75x)')),
                        DropdownMenuItem(value: 1.0, child: Text('中 (1.0x)')),
                        DropdownMenuItem(value: 1.25, child: Text('大 (1.25x)')),
                        DropdownMenuItem(value: 1.5, child: Text('特大 (1.5x)')),
                      ],
                      onChanged: (v) { if (v != null) app.setFontScale(v); },
                    )
                  else
                    SegmentedButton<double>(
                      segments: const [
                        ButtonSegment(value: 0.75, label: Text('小')),
                        ButtonSegment(value: 1.0, label: Text('中')),
                        ButtonSegment(value: 1.25, label: Text('大')),
                        ButtonSegment(value: 1.5, label: Text('特大')),
                      ],
                      selected: {fontScale},
                      onSelectionChanged: (Set<double> selection) {
                        app.setFontScale(selection.first);
                      },
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        textStyle: WidgetStateProperty.all(
                          Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('外观', style: Theme.of(context).textTheme.titleLarge),
                      SizedBox(width: context.gapXHuge),
                      Text('主题', style: Theme.of(context).textTheme.labelLarge),
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
                            Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: context.gapMedium),
                  Row(
                    children: [
                      Text('字号', style: Theme.of(context).textTheme.labelLarge),
                      const Spacer(),
                      SegmentedButton<double>(
                        segments: const [
                          ButtonSegment(value: 0.75, label: Text('小')),
                          ButtonSegment(value: 1.0, label: Text('中')),
                          ButtonSegment(value: 1.25, label: Text('大')),
                          ButtonSegment(value: 1.5, label: Text('特大')),
                        ],
                        selected: {fontScale},
                        onSelectionChanged: (Set<double> selection) {
                          app.setFontScale(selection.first);
                        },
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          textStyle: WidgetStateProperty.all(
                            Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ],
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
                  Text('日志', style: Theme.of(context).textTheme.titleLarge),
                  SizedBox(height: context.gapMedium),
                  Text('日志级别', style: Theme.of(context).textTheme.labelLarge),
                  SizedBox(height: context.gapSmall),
                  SizedBox(
                    width: 150,
                    child: DropdownButtonFormField<String>(
                      value: logLevel,
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
                  Text('日志', style: Theme.of(context).textTheme.titleLarge),
                  SizedBox(width: context.gapXHuge),
                  Text('日志级别', style: Theme.of(context).textTheme.labelLarge),
                  const Spacer(),
                  SizedBox(
                    width: 150,
                    child: DropdownButtonFormField<String>(
                      value: logLevel,
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
            Text('关于', style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: context.gapSmall),
            Text(
              '古典文学阅读推荐系统',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
              ),
            ),
            SizedBox(height: context.gapTiny),
            Text(
              '版本 ${AppState.currentVersion}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
