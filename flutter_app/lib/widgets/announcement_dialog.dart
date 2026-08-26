import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/engine/announcement.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/simple_markdown.dart';

/// 公告 / 作者的话弹窗：内容由 `assets/data/announcement.md` 的 Markdown 数据驱动，
/// 包含作者的话与版本改动，可设置弹出模式。
class AnnouncementDialog extends StatefulWidget {
  final Announcement announcement;
  final AnnouncementMode initialMode;
  final ValueChanged<AnnouncementMode>? onModeChanged;

  const AnnouncementDialog({
    super.key,
    required this.announcement,
    this.initialMode = AnnouncementMode.always,
    this.onModeChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required Announcement announcement,
    AnnouncementMode initialMode = AnnouncementMode.always,
    ValueChanged<AnnouncementMode>? onModeChanged,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AnnouncementDialog(
        announcement: announcement,
        initialMode: initialMode,
        onModeChanged: onModeChanged,
      ),
    );
  }

  @override
  State<AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<AnnouncementDialog> {
  late AnnouncementMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('作者的话'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SimpleMarkdown(data: widget.announcement.markdown),
            const SizedBox(height: 8),
            Divider(color: context.appColors.border, height: 1),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _mode == AnnouncementMode.onUpdate,
              title: const Text('以后只在更新后弹出'),
              subtitle: const Text('关闭后仅在新版本发布时弹出一次'),
              onChanged: (v) {
                setState(() {
                  _mode = v == true
                      ? AnnouncementMode.onUpdate
                      : AnnouncementMode.always;
                });
                widget.onModeChanged?.call(_mode);
              },
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
