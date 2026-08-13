import 'package:flutter/material.dart';

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 多动作对话框（2-3 按钮）：返回被点按钮下标（0-based），null = 取消/关闭
Future<int?> showActionDialog(
  BuildContext context, {
  required String title,
  required String content,
  required List<String> actionLabels,
  String? cancelLabel,
}) async {
  assert(actionLabels.length >= 2 && actionLabels.length <= 3);
  final result = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        if (cancelLabel != null)
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(-1),
            child: Text(cancelLabel),
          ),
        ...List.generate(actionLabels.length, (i) {
          return TextButton(
            onPressed: () => Navigator.of(ctx).pop(i),
            child: Text(actionLabels[i]),
          );
        }),
      ],
    ),
  );
  return result;
}
