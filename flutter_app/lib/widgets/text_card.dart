import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 列表条目卡片：标题 + 副标题 + 尾随组件；
/// 鼠标悬停时边框强调为当前主题色（150ms 过渡由 [AnimatedContainer] 提供）。
class TextCard extends StatefulWidget {
  const TextCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  State<TextCard> createState() => _TextCardState();
}

class _TextCardState extends State<TextCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = _hovering ? context.accent : context.appColors.border;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: InkWell(
        onTap: widget.onTap,
        onHover: (hovering) {
          if (hovering != _hovering) setState(() => _hovering = hovering);
        },
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.cardPaddingH,
            vertical: context.cardPaddingV,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis),
                    if (widget.subtitle != null &&
                        widget.subtitle!.isNotEmpty) ...[
                      SizedBox(height: context.gapTiny),
                      Text(widget.subtitle!,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              widget.trailing,
            ],
          ),
        ),
      ),
    );
  }
}
