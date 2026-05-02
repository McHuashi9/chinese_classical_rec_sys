import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isDark = app.darkMode;

    return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('设置', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 16),
              const Divider(color: AppTheme.border, height: 1),
              const SizedBox(height: 24),
              _buildAppearanceCard(isDark, app),
              const SizedBox(height: 16),
              _buildLoggingCard(isDark, app),
              const SizedBox(height: 16),
              _buildAboutCard(isDark),
            ],
          ),
    );
  }

  Widget _buildAppearanceCard(bool isDark, AppState app) {
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SegmentedButton(
                  label: '亮色',
                  selected: !isDark,
                  onTap: () => app.setDarkMode(false),
                ),
                _SegmentedButton(
                  label: '暗色',
                  selected: isDark,
                  onTap: () => app.setDarkMode(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggingCard(bool isDark, AppState app) {
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
              width: 140,
              child: DropdownButtonFormField<String>(
                initialValue: app.logLevel,
                items: ['INFO', 'DEBUG', 'WARNING', 'ERROR']
                    .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) app.setLogLevel(v);
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

class _SegmentedButton extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentedButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SegmentedButton> createState() => _SegmentedButtonState();
}

class _SegmentedButtonState extends State<_SegmentedButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.selected
        ? AppTheme.vermilion
        : _hovered
            ? AppTheme.borderLight
            : Colors.transparent;
    final fgColor = widget.selected ? Colors.white : AppTheme.ink;

    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 56,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 14,
              fontFamily: AppTheme.fontUI,
              color: fgColor,
            ),
          ),
        ),
      ),
    );
  }
}
