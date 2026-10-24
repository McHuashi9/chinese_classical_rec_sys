import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:chinese_classical_rec_sys/engine/feedback_mailto.dart';
import 'package:chinese_classical_rec_sys/pages/settings/platform.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 日志卡：日志级别选择；桌面端额外提供“打开日志目录”。
class LoggingSection extends StatelessWidget {
  const LoggingSection({super.key});

  @override
  Widget build(BuildContext context) {
    final logLevel = context.select((SettingsController s) => s.logLevel);
    final fontScale = context.select((SettingsController s) => s.fontScale);
    final isSmall = MediaQuery.sizeOf(context).width < 480;
    final isDesktop = isDesktopPlatform;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(context.cardPaddingH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bug_report_outlined, size: 20 * fontScale),
                SizedBox(width: context.gapSmall),
                Text('日志', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            SizedBox(height: context.gapSmall),
            Row(
              children: [
                Text('日志级别', style: Theme.of(context).textTheme.labelLarge),
                SizedBox(width: isSmall ? context.gapXl : 0),
                if (!isSmall) const Spacer(),
                SizedBox(
                  width: isSmall ? 150.0 : 220.0,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(logLevel),
                    initialValue: logLevel,
                    // A5：取值域单一源——白名单即下拉项（脏 prefs 已被归一）。
                    items: SettingsController.logLevelOptions
                        .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        context.read<SettingsController>().setLogLevel(v);
                      }
                    },
                  ),
                ),
              ],
            ),
            if (isDesktop) ...[
              SizedBox(height: context.gapSmall),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _openLogLocation(context),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('打开日志目录'),
                ),
              ),
            ] else ...[
              SizedBox(height: context.gapSmall),
              Text(
                // A4：事实描述——移动端日志只进系统日志，不随反馈自动附带。
                kMobileSystemLogNotice,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.appColors.inkSecondary,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _openLogLocation(BuildContext context) async {
  try {
    final supportDir = await getApplicationSupportDirectory();
    final logDir = Directory('${supportDir.path}/logs');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }
    final ok = await launchUrl(Uri.file(logDir.path),
        mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开日志目录')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开日志目录：$e')),
      );
    }
  }
}
