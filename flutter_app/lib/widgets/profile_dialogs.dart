import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chinese_classical_rec_sys/models/user_profile.dart';
import 'package:chinese_classical_rec_sys/engine/profile_repository.dart';

/// 首次建档引导是否已展示的 SharedPreferences 标记。
const String kProfileOnboardedKey = 'profile_onboarded';

/// 新用户欢迎页是否已展示的 SharedPreferences 标记。
const String kNewUserWelcomeSeenKey = 'new_user_welcome_seen';

/// 新用户欢迎页是否应展示。
///
/// 只有从未展示过欢迎页、当前只有 1 个档案且当前档案未初始化时才展示。
bool shouldShowNewUserWelcome(
  SharedPreferences prefs,
  List<UserProfile> profiles,
  bool isInitialized,
) {
  return !prefs.containsKey(kNewUserWelcomeSeenKey) &&
      profiles.length == 1 &&
      !isInitialized;
}

/// 写入“已展示新用户欢迎页”标记。
Future<void> markNewUserWelcomeSeen(SharedPreferences prefs) async {
  await prefs.setBool(kNewUserWelcomeSeenKey, true);
}

/// 写入“已展示首次建档引导”标记。
Future<void> markProfileOnboardingSeen(SharedPreferences prefs) async {
  await prefs.setBool(kProfileOnboardedKey, true);
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
