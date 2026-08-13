import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 划线原句展示：目标词以 vermilion 实线下划线（与题干"划线词"措辞一致）。
/// [text] 为空时整体不渲染；mark 区间非法时降级为纯文本。
/// 注意：markStart/markLen 为码点语义（C++ 侧/生成器产出），Dart 直接下标切片
/// 依赖 UTF-16 单元 == 码点；当前语料全 BMP 成立，若未来引入扩展区字符需改 runes 重算。
class MarkedSentence extends StatelessWidget {
  final String text;
  final int markStart;
  final int markLen;
  final TextStyle style;

  const MarkedSentence({
    super.key,
    required this.text,
    required this.markStart,
    required this.markLen,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final start = (markStart >= 0 && markStart < text.length) ? markStart : -1;
    final len =
        start >= 0 ? markLen.clamp(1, text.length - start).toInt() : 0;
    if (start < 0) {
      return Text(text, style: style);
    }
    final markColor = context.accent;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, start + len),
            style: style.copyWith(
              color: markColor,
              decoration: TextDecoration.underline,
              decorationColor: markColor,
              decorationThickness: 1.5,
            ),
          ),
          TextSpan(text: text.substring(start + len)),
        ],
      ),
      style: style,
    );
  }
}
