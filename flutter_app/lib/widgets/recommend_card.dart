import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';

/// 推荐结果卡片
class RecommendCard extends StatelessWidget {
  final RecommendResult result;

  const RecommendCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final prob = (result.probability * 100).toStringAsFixed(1);
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        title: Text(result.text.title, style: theme.textTheme.titleLarge),
        subtitle: Text('${result.text.author} · ${result.text.dynasty}'),
        trailing: Text('$prob%',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            )),
        onTap: () {
          context.read<AppState>().loadTextForReading(result.text.id);
        },
      ),
    );
  }
}
