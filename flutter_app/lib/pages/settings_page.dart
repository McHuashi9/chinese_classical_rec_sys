import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.select((AppState a) => a.darkMode);
    final logLevel = context.select((AppState a) => a.logLevel);

    return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('设置', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 16),
              const Divider(color: AppTheme.border, height: 1),
              const SizedBox(height: 24),
              _buildAppearanceCard(context, isDark),
              const SizedBox(height: 16),
              _buildLoggingCard(context, isDark, logLevel),
              const SizedBox(height: 16),
              _buildAboutCard(isDark),
            ],
          ),
    );
  }

  Widget _buildAppearanceCard(BuildContext context, bool isDark) {
    final app = context.read<AppState>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text(
              '外观',
              style: TextStyle(
                fontSize: 20,
                fontFamily: AppTheme.fontTitle,
                color: isDark ? AppTheme.darkInk : AppTheme.ink,
              ),
            ),
            const SizedBox(width: 24),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text(
              '日志',
              style: TextStyle(
                fontSize: 20,
                fontFamily: AppTheme.fontTitle,
                color: isDark ? AppTheme.darkInk : AppTheme.ink,
              ),
            ),
            const SizedBox(width: 24),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            const SizedBox(height: 4),
            Text(
              '古典文学阅读推荐系统',
              style: TextStyle(
                fontSize: 16,
                fontFamily: AppTheme.fontUI,
                color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '版本 v0.2.0',
              style: TextStyle(
                fontSize: 14,
                fontFamily: AppTheme.fontUI,
                color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
