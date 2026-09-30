import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/pages/settings/about_section.dart';
import 'package:chinese_classical_rec_sys/pages/settings/platform.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/screenshot_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/feedback_dialog.dart';

/// 数据与反馈卡：存储状态、导出学习数据、软件内截图、Bug 反馈入口。
class DataFeedbackSection extends StatelessWidget {
  const DataFeedbackSection({super.key});

  @override
  Widget build(BuildContext context) {
    final fontScale = context.select((SettingsController s) => s.fontScale);
    final theme = Theme.of(context);
    final coord = context.read<AppCoordinator>();
    final secondaryColor = context.appColors.inkSecondary;
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: context.cardPaddingH, vertical: context.cardPaddingV),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage_outlined, size: 20 * fontScale),
                SizedBox(width: context.gapSmall),
                Text('数据与反馈', style: theme.textTheme.titleLarge),
              ],
            ),
            SizedBox(height: context.gapSmall),
            AboutDataRow(
              icon: Icons.health_and_safety_outlined,
              label: '存储状态',
              value: coord.isInitialized
                  ? '内容库/用户库就绪'
                  : '异常（${_dbErrorText(coord.dbOpenErrorCode)}）',
              color: secondaryColor,
              fontScale: fontScale,
            ),
            SizedBox(height: context.gapMedium),
            Divider(color: context.appColors.border, height: 1),
            SizedBox(height: context.gapMedium),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.file_upload_outlined,
                  size: 20 * fontScale, color: secondaryColor),
              title: Text('导出学习数据',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: secondaryColor)),
              subtitle: const Text('生成 user.db 快照，可发给开发者用于参数校准'),
              trailing: Icon(Icons.chevron_right,
                  size: 20 * fontScale, color: secondaryColor),
              onTap: () => _exportLearningData(context),
            ),
            SizedBox(height: context.gapSmall),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.photo_camera_outlined,
                  size: 20 * fontScale, color: secondaryColor),
              title: Text('软件内截图',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: secondaryColor)),
              subtitle: const Text('截取当前界面，可附带反馈'),
              trailing: Icon(Icons.chevron_right,
                  size: 20 * fontScale, color: secondaryColor),
              onTap: () => _openScreenshotMode(context),
            ),
            if (isDesktopPlatform)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _openScreenshotDirectory(context),
                    icon: Icon(Icons.folder_open_outlined,
                        size: 16 * fontScale, color: secondaryColor),
                    label: Text('打开截图目录',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: secondaryColor)),
                  ),
                ),
              )
            else if (context
                    .select<ScreenshotController, String?>((c) => c.lastPath) !=
                null)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _shareLastScreenshot(context),
                    icon: Icon(Icons.share_outlined,
                        size: 16 * fontScale, color: secondaryColor),
                    label: Text('分享最近截图',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: secondaryColor)),
                  ),
                ),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.feedback_outlined,
                  size: 20 * fontScale, color: secondaryColor),
              title: Text('反馈 Bug / 意见',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: secondaryColor)),
              trailing: Icon(Icons.chevron_right,
                  size: 20 * fontScale, color: secondaryColor),
              onTap: () => _openFeedbackDialog(context, coord),
            ),
          ],
        ),
      ),
    );
  }
}

void _openFeedbackDialog(BuildContext context, AppCoordinator coord) {
  final schema = coord.schemaVersions;
  final schemaText =
      schema == null ? '不可用' : '用户 ${schema.$1} · 内容 ${schema.$2}';
  showFeedbackDialog(
    context,
    appVersion: AppCoordinator.currentVersion,
    platform: defaultTargetPlatform.name,
    contentDataVersion: coord.contentDataVersion,
    schemaVersions: schemaText,
  );
}

void _openScreenshotMode(BuildContext context) {
  final screenshotCtrl = context.read<ScreenshotController>();
  if (screenshotCtrl.armed) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('截图模式已开启，请切换到目标界面后确认')),
    );
    return;
  }
  screenshotCtrl.arm();
}

Future<void> _openScreenshotDirectory(BuildContext context) async {
  try {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory('${supportDir.path}/screenshots');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final ok = await launchUrl(Uri.file(dir.path),
        mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开截图目录')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开截图目录：$e')),
      );
    }
  }
}

Future<void> _shareLastScreenshot(BuildContext context) async {
  final path = context.read<ScreenshotController>().lastPath;
  if (path == null) return;
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        title: '文言文推荐系统截图',
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享截图失败：$e')),
      );
    }
  }
}

String _exportFileName() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return 'profile_backup_${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}.db';
}

Future<void> _exportLearningData(BuildContext context) async {
  final coord = context.read<AppCoordinator>();
  final bridge = coord.bridge;
  if (bridge == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('核心引擎未就绪，无法导出')),
      );
    }
    return;
  }

  final filename = _exportFileName();
  try {
    if (isDesktopPlatform) {
      final location = await getSaveLocation(
        suggestedName: filename,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'SQLite 数据库', extensions: ['db']),
        ],
      );
      if (location == null) return;
      final path = location.path;
      final pathPtr = path.toNativeUtf8(allocator: calloc);
      final rc = bridge.userExport(pathPtr);
      calloc.free(pathPtr);
      if (!context.mounted) return;
      if (rc == BridgeError.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出到 $path')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出失败，请重试')),
        );
      }
    } else {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      if (file.existsSync()) await file.delete();
      final pathPtr = file.path.toNativeUtf8(allocator: calloc);
      final rc = bridge.userExport(pathPtr);
      calloc.free(pathPtr);
      if (!context.mounted) return;
      if (rc != BridgeError.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出失败，请重试')),
        );
        return;
      }
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        fileNameOverrides: [filename],
        title: '导出学习数据',
      ));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }
}

String _dbErrorText(int? code) {
  switch (code) {
    case BridgeError.errDbContent:
      return '内容库缺失或损坏';
    case BridgeError.errDbUser:
      return '用户库缺失或损坏';
    case BridgeError.errDbVersion:
      return '数据库版本不兼容';
    case BridgeError.errDbSamePath:
      return '内容库与用户库路径相同';
    default:
      return '请重启应用';
  }
}
