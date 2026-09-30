import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 主题色选择器：12 个预设色块 + "+" 自绘 HSV/RGB 取色对话框
class AccentColorSelector extends StatelessWidget {
  const AccentColorSelector({super.key});

  /// 预设主色（传统颜料色）：朱砂为默认，与 design-spec 强调色基调一致
  static const _presets = AppTheme.profileAvatarColors;

  @override
  Widget build(BuildContext context) {
    final current =
        Color(context.select((SettingsController s) => s.accentColorValue));
    final settingsCtrl = context.read<SettingsController>();
    final ringColor = context.appColors.ink;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('主题色', style: Theme.of(context).textTheme.labelLarge),
        SizedBox(height: context.gapSmall),
        Wrap(
          spacing: context.gapMedium,
          runSpacing: context.gapMedium,
          children: [
            for (final color in _presets)
              _AccentSwatch(
                key: ValueKey('accent-preset-${color.toARGB32()}'),
                color: color,
                selected: current == color,
                onTap: () => settingsCtrl.setAccentColor(color.toARGB32()),
                ringColor: ringColor,
              ),
            Tooltip(
              message: '自定义颜色',
              child: _AccentSwatch(
                key: const ValueKey('accent-custom'),
                color: current,
                selected: !_presets.contains(current),
                onTap: () => _pickCustomColor(context, settingsCtrl),
                ringColor: ringColor,
                isCustom: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickCustomColor(
      BuildContext context, SettingsController settingsCtrl) async {
    final current = Color(settingsCtrl.accentColorValue);
    await showDialog<void>(
      context: context,
      builder: (_) => _CustomColorPickerDialog(
        initialColor: current,
        onConfirm: (color) => settingsCtrl.setAccentColor(color.toARGB32()),
      ),
    );
  }
}

/// 自定义主题色对话框：自绘 HSV 色盘 + Hue/RGB 滑杆联动；
/// 窄宽度下不出现 Row 溢出，并提供可操作的 RGB 调整。
class _CustomColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onConfirm;

  const _CustomColorPickerDialog({
    required this.initialColor,
    required this.onConfirm,
  });

  @override
  State<_CustomColorPickerDialog> createState() =>
      _CustomColorPickerDialogState();
}

class _CustomColorPickerDialogState extends State<_CustomColorPickerDialog> {
  late Color _color;

  @override
  void initState() {
    super.initState();
    _color = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(_color);
    return AlertDialog(
      title: const Text('自定义主题色'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 36,
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: context.appColors.border),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: _HsvArea(
                  key: const ValueKey('custom-hsv-area'),
                  hsvColor: hsv,
                  onChanged: (c) => setState(() => _color = c),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('基础色（Hue）',
                      style: Theme.of(context).textTheme.labelLarge),
                  Expanded(
                    child: Slider(
                      value: hsv.hue,
                      max: 360,
                      onChanged: (hue) => setState(() {
                        _color = HSVColor.fromAHSV(
                          1,
                          hue,
                          hsv.saturation,
                          hsv.value,
                        ).toColor();
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _RgbSliders(
                color: _color,
                onChanged: (c) => setState(() => _color = c),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            widget.onConfirm(_color);
            Navigator.of(context).pop();
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 自绘 RGB 滑杆组：三条 0–255 滑杆 + 数值文本。
///
/// 版式对齐被替换的第三方滑杆组件参数：单条 260×40、首字母标签、
/// 右侧数值、无透明通道。
class _RgbSliders extends StatelessWidget {
  const _RgbSliders({required this.color, required this.onChanged});

  final Color color;
  final ValueChanged<Color> onChanged;

  static int _to255(double v) => (v * 255).round().clamp(0, 255);

  @override
  Widget build(BuildContext context) {
    final r = _to255(color.r);
    final g = _to255(color.g);
    final b = _to255(color.b);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        _buildRow(context, 'r', 'R', r,
            (v) => onChanged(Color.fromARGB(255, v, g, b))),
        _buildRow(context, 'g', 'G', g,
            (v) => onChanged(Color.fromARGB(255, r, v, b))),
        _buildRow(context, 'b', 'B', b,
            (v) => onChanged(Color.fromARGB(255, r, g, v))),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildRow(
    BuildContext context,
    String id,
    String label,
    int value,
    ValueChanged<int> onChanged,
  ) {
    return SizedBox(
      width: 260,
      height: 40,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
          Expanded(
            child: Slider(
              key: ValueKey('accent-rgb-$id'),
              value: value.toDouble(),
              max: 255,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 33),
            child: Text(
              '$value',
              key: ValueKey('accent-rgb-$id-value'),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

/// 自绘 HSV 色盘区域：标准 GestureDetector 的 tap/pan 位置映射为饱和度与明度，
/// 避免部分平台/布局下色盘点击不生效的问题。
class _HsvArea extends StatelessWidget {
  final HSVColor hsvColor;
  final ValueChanged<Color> onChanged;

  const _HsvArea({
    super.key,
    required this.hsvColor,
    required this.onChanged,
  });

  void _update(Offset local, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final saturation = (local.dx / size.width).clamp(0.0, 1.0);
    final value = (1 - local.dy / size.height).clamp(0.0, 1.0);
    onChanged(
      HSVColor.fromAHSV(1, hsvColor.hue, saturation, value).toColor(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _update(d.localPosition, size),
          onPanDown: (d) => _update(d.localPosition, size),
          onPanUpdate: (d) => _update(d.localPosition, size),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CustomPaint(
              size: size,
              painter: _HsvAreaPainter(hsvColor),
            ),
          ),
        );
      },
    );
  }
}

/// 自绘 SV 色盘画笔：先铺垂直白→黑渐变，再以 multiply 叠一层水平白→当前色相渐变，
/// 最后在当前饱和度/明度处画描边指示圆。
///
/// [shouldRepaint] 在色相/饱和度/明度变化时返回 true，使指示圆与底色跟随拖动刷新。
class _HsvAreaPainter extends CustomPainter {
  const _HsvAreaPainter(this.hsvColor);

  final HSVColor hsvColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const gradientV = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.white, Colors.black],
    );
    final gradientH = LinearGradient(
      colors: [
        Colors.white,
        HSVColor.fromAHSV(1.0, hsvColor.hue, 1.0, 1.0).toColor(),
      ],
    );
    canvas.drawRect(rect, Paint()..shader = gradientV.createShader(rect));
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.multiply
        ..shader = gradientH.createShader(rect),
    );

    canvas.drawCircle(
      Offset(
        size.width * hsvColor.saturation,
        size.height * (1 - hsvColor.value),
      ),
      size.height * 0.04,
      Paint()
        ..color = _useWhiteForeground(hsvColor.toColor())
            ? Colors.white
            : Colors.black
        ..strokeWidth = 1.5
        ..blendMode = BlendMode.luminosity
        ..style = PaintingStyle.stroke,
    );
  }

  /// 指示圆描边取色判据：加权通道平方和开方 < 130 时用白色，否则黑色。
  static bool _useWhiteForeground(Color color) {
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    final v = math.sqrt(r * r * 0.299 + g * g * 0.587 + b * b * 0.114).round();
    return v < 130;
  }

  @override
  bool shouldRepaint(_HsvAreaPainter oldDelegate) =>
      oldDelegate.hsvColor != hsvColor;
}

/// 单个主题色块：点击选择；鼠标悬停 1.12 倍放大（150ms），触屏无 hover 不受影响
class _AccentSwatch extends StatefulWidget {
  const _AccentSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    required this.ringColor,
    this.isCustom = false,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final Color ringColor;
  final bool isCustom;

  @override
  State<_AccentSwatch> createState() => _AccentSwatchState();
}

class _AccentSwatchState extends State<_AccentSwatch> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final showAdd = widget.isCustom && !widget.selected;
    // 合法例外：取色器色块上根据背景亮度动态计算对比前景色。
    final iconColor =
        widget.color.computeLuminance() > 0.5 ? Colors.black54 : Colors.white;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: widget.onTap,
      onHover: (hovering) {
        if (hovering != _hovering) setState(() => _hovering = hovering);
      },
      child: AnimatedScale(
        scale: _hovering ? 1.12 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // 合法例外：透明仅用于“自定义取色”未选中时的占位。
            color: showAdd ? Colors.transparent : widget.color,
            border: Border.all(
              color: widget.ringColor,
              width: widget.selected || showAdd ? 2 : 0,
            ),
          ),
          child: showAdd
              ? Icon(Icons.add, size: 16, color: widget.ringColor)
              : widget.selected
                  ? Icon(Icons.check, size: 16, color: iconColor)
                  : null,
        ),
      ),
    );
  }
}
