import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/accent_color_picker.dart';
import 'package:chinese_classical_rec_sys/widgets/font_scale_selector.dart';

/// 外观卡：暗色模式、阅读显示选项、主题色与字号。依赖自行从 provider 取。
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsCtrl = context.read<SettingsController>();
    final isDark = context.select((SettingsController s) => s.darkMode);
    final showTranslation =
        context.select((SettingsController s) => s.showTranslation);
    final showRuledLines =
        context.select((SettingsController s) => s.showRuledLines);
    final fontScale = context.select((SettingsController s) => s.fontScale);

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
              onChanged: (v) => settingsCtrl.setDarkMode(v),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('阅读默认显示译文'),
              secondary: const Icon(Icons.translate),
              value: showTranslation,
              onChanged: (v) => settingsCtrl.setShowTranslation(v),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('阅读显示格线'),
              secondary: const Icon(Icons.notes),
              value: showRuledLines,
              onChanged: (v) => settingsCtrl.setShowRuledLines(v),
              contentPadding: EdgeInsets.zero,
            ),
            SizedBox(height: context.gapMedium),
            const AccentColorSelector(),
            SizedBox(height: context.gapMedium),
            const FontScaleSelector(),
          ],
        ),
      ),
    );
  }
}
