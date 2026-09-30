import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 字号选择器：宽屏为分段按钮，窄屏退化为下拉（避免窄宽度挤压）。
class FontScaleSelector extends StatelessWidget {
  const FontScaleSelector({super.key});

  static const _values = SettingsController.fontScaleSteps;
  static const _labels = [
    '0.75x',
    '1.0x',
    '1.25x',
    '1.5x',
    '1.75x',
    '2.0x',
    '2.25x',
    '2.5x',
  ];

  @override
  Widget build(BuildContext context) {
    final fontScale = context.select((SettingsController s) => s.fontScale);
    final settingsCtrl = context.read<SettingsController>();
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
              if (v != null) settingsCtrl.setFontScale(v);
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
            settingsCtrl.setFontScale(selection.first);
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
