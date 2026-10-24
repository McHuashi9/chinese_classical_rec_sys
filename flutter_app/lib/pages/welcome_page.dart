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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 系统返回键 / 手势返回的处理：建档前允许退出。
  ///
  /// 返回等价于“稍后继续”——只 `pop(false)`，由 `main.dart` 端决定不为本次
  /// 退出写入 `new_user_welcome_seen`；初始化门禁照旧，下次启动仍会进入欢迎页。
  /// （`canPop:false` 只关闭默认 pop，必须在此显式收尾，否则返回事件被静默吞掉。）
  void _handlePop(bool didPop, Object? result) {
    if (didPop) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handlePop,
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
                    Icon(Icons.auto_stories, size: 72, color: context.accent),
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
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
