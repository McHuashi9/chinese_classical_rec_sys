import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/engine/chinese_festivals.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 节日弹窗：参考公告弹窗样式，但不提供“以后不再弹出”选项。
class FestivalDialog extends StatelessWidget {
  final Festival festival;

  const FestivalDialog({super.key, required this.festival});

  static Future<void> show(
    BuildContext context, {
    required Festival festival,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FestivalDialog(festival: festival),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(festival.title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              festival.subtitle,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: context.appColors.inkSecondary,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              festival.content,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.7),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.accent,
            foregroundColor: context.appColors.onAccent,
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}
