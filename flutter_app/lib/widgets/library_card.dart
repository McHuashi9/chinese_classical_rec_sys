import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';

/// 文库列表卡片组件
class LibraryCard extends StatelessWidget {
  final ChineseText text;

  const LibraryCard({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(text.title,
            style: Theme.of(context).textTheme.titleLarge),
        subtitle: Text('${text.author} · ${text.dynasty}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          context.read<AppState>().loadTextForReading(text.id);
        },
      ),
    );
  }
}
