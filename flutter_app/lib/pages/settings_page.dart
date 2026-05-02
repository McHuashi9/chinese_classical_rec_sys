import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';

/// 设置页面 — 等价于 QML SettingsPage
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('设置', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 24),
        SwitchListTile(
          title: const Text('暗色模式'),
          value: app.darkMode,
          onChanged: app.setDarkMode,
        ),
        const Divider(),
        ListTile(
          title: const Text('版本'),
          subtitle: const Text('v0.2.0'),
        ),
      ],
    );
  }
}
