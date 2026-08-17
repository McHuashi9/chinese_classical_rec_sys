import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/engine/announcement.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 公告 / 作者的话弹窗：上半作者的话，下半版本改动，按钮「知道了」。
class AnnouncementDialog extends StatelessWidget {
  final Announcement announcement;

  const AnnouncementDialog({super.key, required this.announcement});

  static Future<void> show(
    BuildContext context, {
    required Announcement announcement,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AnnouncementDialog(announcement: announcement),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor =
        isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary;
    return AlertDialog(
      title: const Text('作者的话'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              announcement.authorMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 16),
            const Divider(color: AppTheme.border, height: 1),
            const SizedBox(height: 16),
            Text(
              '版本改动',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: context.accent),
            ),
            const SizedBox(height: 8),
            Text(
              announcement.changes,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: secondaryColor, height: 1.5),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}
