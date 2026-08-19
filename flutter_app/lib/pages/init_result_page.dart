import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 初始化完成页：持有初始化题组内存，销毁时统一释放。
class InitResultPage extends StatefulWidget {
  final List<Question> questions;

  const InitResultPage({super.key, required this.questions});

  @override
  State<InitResultPage> createState() => _InitResultPageState();
}

class _InitResultPageState extends State<InitResultPage> {
  UserController? _userCtrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _userCtrl ??= context.read<UserController>();
  }

  @override
  void dispose() {
    _userCtrl?.disposeQuizQuestions(widget.questions);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.paper,
      appBar: AppBar(
        // 合法例外：AppBar 透明背景以露出 Scaffold 纸色。
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('初始化完成'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle,
                  size: 72, color: context.appColors.success),
              const SizedBox(height: 16),
              Text(
                '能力画像已建立',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '现在可以开始阅读与随堂练习了。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.appColors.inkSecondary,
                    ),
              ),
              const SizedBox(height: 32),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: context.accent,
                  foregroundColor: context.appColors.onAccent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                ),
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('开始使用'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
