import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
import 'package:chinese_classical_rec_sys/widgets/radar_chart.dart';

/// 能力雷达图页面 — 等价于 QML AbilityPage
class AbilityPage extends StatelessWidget {
  const AbilityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final user = app.user;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('能力评估',
              style: Theme.of(context).textTheme.headlineMedium),
        ),
        Expanded(
          child: user != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: RadarChart(
                    values: [
                      for (int i = 0; i < 10; i++) user.getAbility(i),
                    ],
                  ),
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }
}
