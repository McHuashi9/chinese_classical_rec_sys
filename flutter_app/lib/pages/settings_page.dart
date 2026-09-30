import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/pages/settings/about_section.dart';
import 'package:chinese_classical_rec_sys/pages/settings/appearance_section.dart';
import 'package:chinese_classical_rec_sys/pages/settings/data_feedback_section.dart';
import 'package:chinese_classical_rec_sys/pages/settings/logging_section.dart';
import 'package:chinese_classical_rec_sys/pages/settings/profile_section.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 设置页壳：只负责分区卡片编排。
///
/// 各分区自行 `context.select`/`read` 取所需依赖，避免向壳做 prop-drill；
/// 卡片顺序：关于 → 用户档案 → 外观 → 日志 → 数据与反馈。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(context.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设置', style: Theme.of(context).textTheme.headlineLarge),
          SizedBox(height: context.gapLg),
          Divider(color: context.appColors.border, height: 1),
          SizedBox(height: context.gapXl),
          const AboutSection(),
          SizedBox(height: context.gapLg),
          const ProfileSection(),
          SizedBox(height: context.gapLg),
          const AppearanceSection(),
          SizedBox(height: context.gapLg),
          const LoggingSection(),
          SizedBox(height: context.gapLg),
          const DataFeedbackSection(),
        ],
      ),
    );
  }
}
