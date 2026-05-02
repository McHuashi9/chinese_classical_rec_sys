import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';

/// 文库列表卡片组件
class LibraryCard extends StatelessWidget {
  final ChineseText text;

  const LibraryCard({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        title: Text(text.title,
            style: Theme.of(context).textTheme.titleLarge),
        subtitle: Text('${text.author} · ${text.dynasty}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // TODO: 加载阅读页
        },
      ),
    );
  }
}
