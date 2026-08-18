import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/models/user_profile.dart';
import 'package:chinese_classical_rec_sys/engine/profile_repository.dart';
import 'package:chinese_classical_rec_sys/pages/init_onboarding_page.dart';

/// 首次建档引导是否已展示的 SharedPreferences 标记。
const String kProfileOnboardedKey = 'profile_onboarded';

/// 首次建档引导的选项。
enum ProfileOnboardingChoice { useDefault, create, rename, skip }

/// 首次建档引导是否应展示。
///
/// 只有从未展示过，并且当前只有 1 个档案（默认用户）时才展示；
/// 已经建过多个档案的用户视为已知该功能。
bool shouldShowProfileOnboarding(
    SharedPreferences prefs, List<UserProfile> profiles) {
  return !prefs.containsKey(kProfileOnboardedKey) && profiles.length == 1;
}

/// 写入“已展示首次建档引导”标记。
Future<void> markProfileOnboardingSeen(SharedPreferences prefs) async {
  await prefs.setBool(kProfileOnboardedKey, true);
}

/// 首次建档引导弹窗：返回用户选择；关闭弹窗即返回。
Future<ProfileOnboardingChoice?> showProfileOnboardingDialog(
    BuildContext context) {
  return showDialog<ProfileOnboardingChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('管理学习档案'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('你可以为不同的人或不同的学习目标创建独立档案，学习记录互不干扰。'),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person),
              title: const Text('使用默认用户'),
              subtitle: const Text('直接开始学习'),
              onTap: () =>
                  Navigator.of(ctx).pop(ProfileOnboardingChoice.useDefault),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_add),
              title: const Text('新建档案'),
              subtitle: const Text('创建独立的用户档案'),
              onTap: () =>
                  Navigator.of(ctx).pop(ProfileOnboardingChoice.create),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名默认用户'),
              subtitle: const Text('把默认档案改成你的名字'),
              onTap: () =>
                  Navigator.of(ctx).pop(ProfileOnboardingChoice.rename),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(ProfileOnboardingChoice.skip),
          child: const Text('跳过'),
        ),
      ],
    ),
  );
}

/// 执行首次建档引导的完整流程（弹窗 + 新建/重命名动作）。
Future<void> runProfileOnboarding(
    BuildContext context, AppCoordinator coord) async {
  final choice = await showProfileOnboardingDialog(context);
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case ProfileOnboardingChoice.useDefault:
    case ProfileOnboardingChoice.skip:
      return;
    case ProfileOnboardingChoice.create:
      await _createProfileFromOnboarding(context, coord);
    case ProfileOnboardingChoice.rename:
      await _renameDefaultFromOnboarding(context, coord);
  }
}

Future<void> _createProfileFromOnboarding(
    BuildContext context, AppCoordinator coord) async {
  final name = await promptProfileName(context, title: '新建用户档案');
  if (name == null || !context.mounted) return;
  final userCtrl = coord.userCtrl;
  if (userCtrl.isProfileNameTaken(name)) {
    _showSnack(context, '该名称已存在，请换一个');
    return;
  }

  int? id;
  if (userCtrl.isInitialized) {
    // 当前只有 1 个档案时，继承来源就是该档案，无需再弹选择来源。
    final profiles = userCtrl.profiles;
    final source = profiles.isEmpty ? null : profiles.first;
    final method = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SimpleDialog(
        title: const Text('新档案初始化方式'),
        children: [
          ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: const Text('继承已有档案'),
            subtitle: const Text('复制当前档案的能力与阅读历史'),
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
    if (method == 'inherit' && source != null) {
      id = coord.createInheritedProfile(name, source.id);
    } else {
      id = coord.createProfile(name);
    }
  } else {
    id = coord.createProfile(name);
  }

  if (id == null) {
    if (context.mounted) {
      _showSnack(context, '创建失败，请检查名称长度');
    }
    return;
  }
  if (!coord.switchProfile(id)) {
    if (context.mounted) {
      _showSnack(context, '创建成功，但切换失败');
    }
    return;
  }
  coord.userCtrl.refreshInitState();
  // 新建“完成初始化”档案后必须立即进入初始化流程；未完成前退出/杀进程，
  // 下次启动仍会被主流程拦截继续初始化，避免出现“未初始化但有阅读记录”的中间态。
  if (context.mounted && !coord.userCtrl.isInitialized) {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InitOnboardingPage()),
    );
  }
}

Future<void> _renameDefaultFromOnboarding(
    BuildContext context, AppCoordinator coord) async {
  final profiles = coord.userCtrl.profiles;
  if (profiles.isEmpty) return;
  final defaultProfile = profiles.first;
  final name = await promptProfileName(context,
      title: '重命名默认用户', initial: defaultProfile.name);
  if (name == null || !context.mounted) return;
  if (coord.userCtrl.isProfileNameTaken(name, excludeId: defaultProfile.id)) {
    _showSnack(context, '该名称已被其他档案使用');
    return;
  }
  if (!coord.renameProfile(defaultProfile.id, name) && context.mounted) {
    _showSnack(context, '重命名失败，请检查名称长度');
  }
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// 档案命名对话框：返回规范化后的名称；取消返回 null。
Future<String?> promptProfileName(
  BuildContext context, {
  required String title,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '请输入用户名称',
        ),
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  // 不手动 dispose controller：对话框关闭动画期间 TextField 仍持有监听。
  // 局部 controller 随 GC 回收，短生命周期可接受。
  final name = result?.trim();
  if (name == null) return null;
  if (!context.mounted) return null;
  if (name.isEmpty) {
    _showSnack(context, '名称不能为空');
    return null;
  }
  if (utf8.encode(name).length > maxProfileNameBytes) {
    _showSnack(context, '名称过长，请缩短');
    return null;
  }
  return normalizeProfileName(name);
}
