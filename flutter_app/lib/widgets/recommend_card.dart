import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';

/// 推荐结果卡片
class RecommendCard extends StatelessWidget {
  final RecommendResult result;

  const RecommendCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final prob = (result.probability * 100).toStringAsFixed(1);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        title: Text(result.text.title,
            style: Theme.of(context).textTheme.titleLarge),
        subtitle: Text('${result.text.author} · ${result.text.dynasty}'),
        trailing: Text('$prob%',
            style: Theme.of(context).textTheme.bodyMedium),
        onTap: () {
          // TODO: 加载阅读页
        },
      ),
    );
  }
}
