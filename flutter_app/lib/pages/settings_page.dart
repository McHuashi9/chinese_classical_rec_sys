import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:chinese_classical_rec_sys/widgets/feedback_dialog.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/models/version.dart';
import 'package:chinese_classical_rec_sys/models/user_profile.dart';
import 'package:chinese_classical_rec_sys/engine/profile_repository.dart';
import 'package:chinese_classical_rec_sys/widgets/dialogs.dart';
import 'package:chinese_classical_rec_sys/widgets/announcement_dialog.dart';
import 'package:chinese_classical_rec_sys/pages/init_onboarding_page.dart';
import 'package:chinese_classical_rec_sys/widgets/profile_dialogs.dart';
import 'package:chinese_classical_rec_sys/widgets/profile_avatar.dart';
import 'package:chinese_classical_rec_sys/engine/announcement.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/engine/github_config.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _checking = false;

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    final isDark = context.select((SettingsController s) => s.darkMode);
    final fontScale = context.select((SettingsController s) => s.fontScale);
    final logLevel = context.select((SettingsController s) => s.logLevel);
    final isSmall = MediaQuery.sizeOf(context).width < 480;

    return SingleChildScrollView(
      padding: EdgeInsets.all(context.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设置', style: Theme.of(context).textTheme.headlineLarge),
          SizedBox(height: context.gapLg),
          Divider(color: context.appColors.border, height: 1),
          SizedBox(height: context.gapXl),
          _buildAboutCard(fontScale),
          SizedBox(height: context.gapLg),
          _buildProfileCard(context, fontScale),
          SizedBox(height: context.gapLg),
          _buildAppearanceCard(context, isDark, fontScale),
          SizedBox(height: context.gapLg),
          _buildLoggingCard(context, isSmall, logLevel, fontScale),
          SizedBox(height: context.gapLg),
          _buildDataFeedbackCard(fontScale),
        ],
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, double fontScale) {
    final profiles = context.select((UserController u) => u.profiles);
    final activeUserId = context.select((UserController u) => u.activeUserId);
    final coord = context.read<AppCoordinator>();

    return Card(
      child: Padding(
        padding: EdgeInsets.all(context.cardPaddingH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.people_outline, size: 20 * fontScale),
                SizedBox(width: context.gapSmall),
                Text('用户档案', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  tooltip: profiles.length >= kMaxProfiles
                      ? '已达档案数上限（$kMaxProfiles）'
                      : '新建用户',
                  icon: const Icon(Icons.person_add),
                  onPressed: profiles.length >= kMaxProfiles
                      ? null
                      : () => _showCreateProfileDialog(context, coord),
                ),
              ],
            ),
            SizedBox(height: context.gapSmall),
            if (profiles.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: context.gapMedium),
                child: Text('暂无用户档案',
                    style: Theme.of(context).textTheme.bodyMedium),
              )
            else
              ...profiles.map((p) {
                final isActive = p.id == activeUserId;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ProfileAvatar(name: p.name, id: p.id),
                  title: Text(p.name),
                  subtitle: Text(
                    isActive
                        ? '当前使用 · 最后使用 ${_formatLastUsed(p.lastUsedAt)}'
                        : '最后使用 ${_formatLastUsed(p.lastUsedAt)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '重命名',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () =>
                            _showRenameProfileDialog(context, coord, p),
                      ),
                      IconButton(
                        tooltip: isActive ? '不能删除当前用户' : '删除',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: isActive
                            ? null
                            : () => _showDeleteProfileDialog(context, coord, p),
                      ),
                    ],
                  ),
                  onTap:
                      isActive ? null : () => _switchProfile(context, coord, p),
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _switchProfile(
      BuildContext context, AppCoordinator coord, UserProfile profile) async {
    final ok = coord.switchProfile(profile.id);
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换到「${profile.name}」')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('切换用户失败（${profile.name}）')),
      );
    }
  }

  Future<void> _showCreateProfileDialog(
      BuildContext context, AppCoordinator coord) async {
    final name = await promptProfileName(context, title: '新建用户档案');
    if (name == null || !context.mounted) return;
    // 重名预检查给友好提示（C++ 侧同样拒绝，双保险）
    if (coord.userCtrl.isProfileNameTaken(name)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该名称已存在，请换一个')),
        );
      }
      return;
    }
    // 新档案二选一：继承已有档案 / 完成初始化（强制初始化完成前不能正常使用）
    final method = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SimpleDialog(
        title: const Text('新档案初始化方式'),
        children: [
          ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: const Text('继承已有档案'),
            subtitle: const Text('复制某个档案的能力与阅读历史'),
            onTap: () => Navigator.of(ctx).pop('inherit'),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('完成初始化'),
            subtitle: const Text('新档案从零开始，完成 6 道初始化题'),
            onTap: () => Navigator.of(ctx).pop('init'),
          ),
        ],
      ),
    );
    if (!context.mounted || method == null) return;

    if (method == 'inherit') {
      final source = await _pickSourceProfile(context, coord);
      if (source == null || !context.mounted) return;
      final id = coord.createInheritedProfile(name, source.id);
      if (id == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('创建失败，请检查名称长度')),
          );
        }
        return;
      }
      if (!coord.switchProfile(id)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('创建成功，但切换失败')),
          );
        }
        return;
      }
      coord.userCtrl.refreshInitState();
      return;
    }

    final id = coord.createProfile(name);
    if (id == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('创建失败，请检查名称长度')),
        );
      }
      return;
    }
    if (!coord.switchProfile(id)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('创建成功，但切换失败')),
        );
      }
      return;
    }
    coord.userCtrl.refreshInitState();
    if (context.mounted && !coord.userCtrl.isInitialized) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const InitOnboardingPage()),
      );
    }
  }

  Future<UserProfile?> _pickSourceProfile(
      BuildContext context, AppCoordinator coord) async {
    final profiles = coord.userCtrl.profiles;
    if (profiles.isEmpty) return null;
    return showDialog<UserProfile>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择要继承的档案'),
        children: [
          for (final p in profiles)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(p.name),
              onTap: () => Navigator.of(ctx).pop(p),
            ),
        ],
      ),
    );
  }

  Future<void> _showRenameProfileDialog(
      BuildContext context, AppCoordinator coord, UserProfile profile) async {
    final name =
        await promptProfileName(context, title: '重命名用户', initial: profile.name);
    if (name == null || !context.mounted) return;
    // 排除自身后重名才算冲突
    if (coord.userCtrl.isProfileNameTaken(name, excludeId: profile.id)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该名称已被其他档案使用')),
        );
      }
      return;
    }
    if (!coord.renameProfile(profile.id, name)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('重命名失败，请检查名称长度')),
        );
      }
    }
  }

  Future<void> _showDeleteProfileDialog(
      BuildContext context, AppCoordinator coord, UserProfile profile) async {
    final confirmed = await showConfirmDialog(context,
        title: '删除用户档案',
        content: '确定删除「${profile.name}」吗？该档案的学习记录将被永久删除，无法恢复。',
        confirmLabel: '删除');
    if (confirmed && context.mounted) {
      if (!coord.deleteProfile(profile.id) && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除失败')),
        );
      }
    }
  }

  Widget _buildAppearanceCard(
      BuildContext context, bool isDark, double fontScale) {
    final settingsCtrl = context.read<SettingsController>();
    final showTranslation =
        context.select((SettingsController s) => s.showTranslation);
    final showRuledLines =
        context.select((SettingsController s) => s.showRuledLines);
    return Card(
      child: Padding(
        padding: EdgeInsets.all(context.cardPaddingH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.palette_outlined, size: 20 * fontScale),
                SizedBox(width: context.gapSmall),
                Text('外观', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            SizedBox(height: context.gapSmall),
            SwitchListTile(
              title: const Text('暗色模式'),
              secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
              value: isDark,
              onChanged: (v) => settingsCtrl.setDarkMode(v),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('阅读默认显示译文'),
              secondary: const Icon(Icons.translate),
              value: showTranslation,
              onChanged: (v) => settingsCtrl.setShowTranslation(v),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('阅读显示格线'),
              secondary: const Icon(Icons.notes),
              value: showRuledLines,
              onChanged: (v) => settingsCtrl.setShowRuledLines(v),
              contentPadding: EdgeInsets.zero,
            ),
            SizedBox(height: context.gapMedium),
            const _AccentColorSelector(),
            SizedBox(height: context.gapMedium),
            const _FontScaleSelector(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggingCard(
      BuildContext context, bool isSmall, String logLevel, double fontScale) {
    final isDesktop = _isDesktop;
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
                    items: ['INFO', 'DEBUG', 'WARN', 'ERROR']
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
                  onPressed: _openLogLocation,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('打开日志所在位置'),
                ),
              ),
            ] else ...[
              SizedBox(height: context.gapSmall),
              Text(
                '移动端日志已包含在反馈中',
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

  Widget _buildAboutCard(double fontScale) {
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
                Icon(Icons.info_outline, size: 20 * fontScale),
                SizedBox(width: context.gapSmall),
                Text('关于', style: theme.textTheme.titleLarge),
              ],
            ),
            SizedBox(height: context.gapSmall),
            Row(
              children: [
                Text('文言文推荐系统',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: secondaryColor)),
                const Spacer(),
                Text('v${AppCoordinator.currentVersion}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: secondaryColor)),
              ],
            ),
            SizedBox(height: context.gapMedium),
            _AboutDataRow(
              icon: Icons.storage_outlined,
              label: '内容数据版本',
              value: coord.contentDataVersion,
              color: secondaryColor,
              fontScale: fontScale,
            ),
            SizedBox(height: context.gapSmall),
            _AboutDataRow(
              icon: Icons.dataset_outlined,
              label: '数据库格式版本',
              value: coord.schemaVersions == null
                  ? '不可用'
                  : '内容 ${coord.schemaVersions!.$2} · 用户 ${coord.schemaVersions!.$1}',
              color: secondaryColor,
              fontScale: fontScale,
            ),
            SizedBox(height: context.gapMedium),
            Divider(color: context.appColors.border, height: 1),
            SizedBox(height: context.gapMedium),
            _AboutLinkRow(
              icon: Icons.code,
              label: 'GitHub 仓库',
              url: GithubConfig.repoUrl,
              fontScale: fontScale,
              color: secondaryColor,
            ),
            SizedBox(height: context.gapSmall),
            _AboutLinkRow(
              icon: Icons.update,
              label: '更新日志',
              url: GithubConfig.releasesUrl,
              fontScale: fontScale,
              color: secondaryColor,
            ),
            SizedBox(height: context.gapSmall),
            InkWell(
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                if (!mounted) return;
                await AnnouncementDialog.show(
                  context,
                  announcement: kCurrentAnnouncement,
                  initialMode: loadAnnouncementMode(prefs),
                  onModeChanged: (m) async {
                    await saveAnnouncementMode(prefs, m);
                  },
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.campaign_outlined,
                        size: 16 * fontScale, color: secondaryColor),
                    SizedBox(width: context.gapSmall),
                    Text('公告 / 作者的话',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: secondaryColor)),
                  ],
                ),
              ),
            ),
            SizedBox(height: context.gapMedium),
            Row(
              children: [
                Icon(Icons.mail_outline,
                    size: 16 * fontScale, color: secondaryColor),
                SizedBox(width: context.gapSmall),
                Expanded(
                  child: Text('mc_huashi9@163.com',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: secondaryColor)),
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(
                        const ClipboardData(text: 'mc_huashi9@163.com'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('邮箱已复制'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4 * fontScale),
                    child: Icon(Icons.copy,
                        size: 16 * fontScale, color: secondaryColor),
                  ),
                ),
              ],
            ),
            SizedBox(height: context.gapMedium),
            Row(
              children: [
                Icon(Icons.article,
                    size: 16 * fontScale, color: secondaryColor),
                SizedBox(width: context.gapSmall),
                Text('MIT License',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: secondaryColor)),
              ],
            ),
            SizedBox(height: context.gapMedium),
            Divider(color: context.appColors.border, height: 1),
            SizedBox(height: context.gapMedium),
            _buildCheckUpdateButton(context, fontScale),
          ],
        ),
      ),
    );
  }

  Widget _buildDataFeedbackCard(double fontScale) {
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
            _AboutDataRow(
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
              onTap: _exportLearningData,
            ),
            SizedBox(height: context.gapSmall),
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

  Future<void> _openLogLocation() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final logDir = Directory('${supportDir.path}/logs');
      final logFile = File('${logDir.path}/app.log');
      final uri =
          logFile.existsSync() ? Uri.file(logFile.path) : Uri.file(logDir.path);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开日志位置')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开日志位置：$e')),
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

  Future<void> _exportLearningData() async {
    final coord = context.read<AppCoordinator>();
    final bridge = coord.bridge;
    if (bridge == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('核心引擎未就绪，无法导出')),
        );
      }
      return;
    }

    final filename = _exportFileName();
    try {
      if (_isDesktop) {
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
        if (!mounted) return;
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
        if (!mounted) return;
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
      if (mounted) {
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

  Widget _buildCheckUpdateButton(BuildContext context, double fontScale) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _checking ? null : () => _checkForUpdates(context),
        icon: _checking
            ? SizedBox(
                width: 16 * fontScale,
                height: 16 * fontScale,
                child: CircularProgressIndicator(strokeWidth: 2 * fontScale),
              )
            : Icon(Icons.system_update, size: 18 * fontScale),
        label: Text(_checking ? '检查中...' : '检查更新'),
      ),
    );
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    if (_checking) return;
    setState(() => _checking = true);

    final settingsCtrl = context.read<SettingsController>();
    final messenger = ScaffoldMessenger.of(context);
    final current = Version.parse(AppCoordinator.currentVersion);

    try {
      final latest = await settingsCtrl
          .manualCheckForUpdates(AppCoordinator.currentVersion);

      if (!mounted) return;

      if (latest == null) {
        final reason = settingsCtrl.updateCheckError ?? '网络不可用，请稍后重试';
        messenger.showSnackBar(SnackBar(content: Text(reason)));
      } else if (latest == current) {
        messenger.showSnackBar(
          const SnackBar(
              content: Text('已是最新版本 ${AppCoordinator.currentVersion}')),
        );
      } else if (latest > current) {
        await _showUpdateDialog(latest.toString());
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _showUpdateDialog(String latestVersion) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 v$latestVersion'),
        content: const Text('当前版本: ${AppCoordinator.currentVersion}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () {
              _launch(
                ctx,
                GithubConfig.releaseTagUrl(latestVersion),
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('前往下载'),
          ),
        ],
      ),
    );
  }
}

void _launch(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await launchUrl(Uri.parse(url));
  } catch (_) {
    try {
      messenger.showSnackBar(
        SnackBar(content: Text('无法打开浏览器，请手动访问: $url')),
      );
    } catch (_) {}
  }
}

String _formatLastUsed(int timestamp) {
  if (timestamp <= 0) return '从未使用';
  final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

class _AboutDataRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final double fontScale;

  const _AboutDataRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.fontScale,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16 * fontScale, color: color),
        SizedBox(width: context.gapSmall),
        Text(label,
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _AboutLinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;
  final double fontScale;
  final Color color;

  const _AboutLinkRow({
    required this.icon,
    required this.label,
    required this.url,
    required this.fontScale,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _launch(context, url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 16 * fontScale, color: color),
            SizedBox(width: context.gapSmall),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

/// 主题色选择器：12 个预设色块 + "+" 自定义取色（flutter_colorpicker）
class _AccentColorSelector extends StatelessWidget {
  const _AccentColorSelector();

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

/// 自定义主题色对话框：色盘 + RGB 滑杆联动，避免 flutter_colorpicker
/// 在横屏/窄宽度下的 Row 溢出，并提供可操作的 RGB 调整。
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
              SlidePicker(
                pickerColor: _color,
                onColorChanged: (c) => setState(() => _color = c),
                colorModel: ColorModel.rgb,
                enableAlpha: false,
                showIndicator: false,
                labelTypes: const [],
                sliderSize: const Size(260, 40),
                showSliderText: true,
                showParams: true,
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

/// 自绘 HSV 色盘区域：用标准 GestureDetector 替代 flutter_colorpicker 的
/// RawGestureDetector，避免部分平台/布局下色盘点击不生效的问题。
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
              painter: HSVWithHueColorPainter(hsvColor),
            ),
          ),
        );
      },
    );
  }
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

class _FontScaleSelector extends StatelessWidget {
  const _FontScaleSelector();

  static const _values = SettingsController.fontScaleSteps;
  static const _labels = [
    '0.75x',
    '1.0x',
    '1.25x',
    '1.5x',
    '1.75x',
    '2.0x',
    '2.25x',
    '2.5x',
  ];

  @override
  Widget build(BuildContext context) {
    final fontScale = context.select((SettingsController s) => s.fontScale);
    final settingsCtrl = context.read<SettingsController>();
    final isSmall = MediaQuery.sizeOf(context).width < 480;

    if (isSmall) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('字号', style: Theme.of(context).textTheme.labelLarge),
          SizedBox(height: context.gapSmall),
          DropdownButton<double>(
            value: fontScale,
            items: [
              for (var i = 0; i < _values.length; i++)
                DropdownMenuItem(value: _values[i], child: Text(_labels[i])),
            ],
            onChanged: (v) {
              if (v != null) settingsCtrl.setFontScale(v);
            },
          ),
        ],
      );
    }
    return Row(
      children: [
        Text('字号', style: Theme.of(context).textTheme.labelLarge),
        const Spacer(),
        SegmentedButton<double>(
          segments: [
            for (var i = 0; i < _values.length; i++)
              ButtonSegment(value: _values[i], label: Text(_labels[i])),
          ],
          selected: {fontScale},
          onSelectionChanged: (Set<double> selection) {
            settingsCtrl.setFontScale(selection.first);
          },
          style: ButtonStyle(
            textStyle: WidgetStateProperty.all(
              Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }
}
