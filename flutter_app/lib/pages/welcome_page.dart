import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/engine/profile_repository.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 新用户全屏欢迎页：输入用户名后重命名默认档案并进入初始化。
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final TextEditingController _nameController =
      TextEditingController(text: '默认用户');
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_submitting) return;
    final coord = context.read<AppCoordinator>();
    final profiles = coord.userCtrl.profiles;
    if (profiles.isEmpty) {
      Navigator.of(context).pop(true);
      return;
    }
    final defaultProfile = profiles.first;

    var name = _nameController.text.trim();
    if (name.isEmpty) {
      name = '默认用户';
    }
    final normalized = normalizeProfileName(name);
    if (normalized == null) {
      _showSnack('名称过长，请缩短');
      return;
    }
    if (coord.userCtrl.isProfileNameTaken(normalized,
        excludeId: defaultProfile.id)) {
      _showSnack('该名称已被其他档案使用');
      return;
    }

    setState(() => _submitting = true);
    final ok = normalized == defaultProfile.name ||
        coord.renameProfile(defaultProfile.id, normalized);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!ok) {
      _showSnack('重命名失败，请检查名称长度');
      return;
    }
    Navigator.of(context).pop(true);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: context.appColors.paper,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(context.pagePadding),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.auto_stories,
                        size: 72, color: context.accent),
                    SizedBox(height: context.gapLg),
                    Text(
                      '欢迎使用文言文推荐系统',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    SizedBox(height: context.gapMedium),
                    Text(
                      '给自己起个名字，之后可在设置中修改。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(color: context.appColors.inkSecondary),
                    ),
                    SizedBox(height: context.gapXl),
                    TextField(
                      controller: _nameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        hintText: '默认用户',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      onSubmitted: (_) => _start(),
                    ),
                    SizedBox(height: context.gapLg),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: context.accent,
                        foregroundColor: context.appColors.onAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      onPressed: _submitting ? null : _start,
                      child: Text(_submitting ? '正在初始化…' : '开始初始化'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
