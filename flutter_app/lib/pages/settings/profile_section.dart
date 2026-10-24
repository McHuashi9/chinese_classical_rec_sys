import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/engine/profile_repository.dart';
import 'package:chinese_classical_rec_sys/models/user_profile.dart';
import 'package:chinese_classical_rec_sys/pages/init_onboarding_page.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/dialogs.dart';
import 'package:chinese_classical_rec_sys/widgets/profile_avatar.dart';
import 'package:chinese_classical_rec_sys/widgets/profile_dialogs.dart';

/// 用户档案卡：列出档案并支持新建 / 重命名 / 删除 / 切换。
class ProfileSection extends StatelessWidget {
  const ProfileSection({super.key});

  @override
  Widget build(BuildContext context) {
    final fontScale = context.select((SettingsController s) => s.fontScale);
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
}

Future<void> _switchProfile(
    BuildContext context, AppCoordinator coord, UserProfile profile) async {
  final ok = coord.switchProfile(profile.id);
  if (!context.mounted) return;
  if (ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已切换到“${profile.name}”')),
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
      content: '确定删除“${profile.name}”吗？该档案的学习记录将被永久删除，无法恢复。',
      confirmLabel: '删除');
  if (confirmed && context.mounted) {
    if (!coord.deleteProfile(profile.id) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败')),
      );
    }
  }
}

String _formatLastUsed(int timestamp) {
  if (timestamp <= 0) return '从未使用';
  final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}
