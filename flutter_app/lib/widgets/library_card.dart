import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/dialogs.dart';

class LibraryCard extends StatelessWidget {
  final ChineseText text;

  const LibraryCard({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: () async {
          final app = context.read<AppState>();
          if (app.hasUnrecordedReading && app.readingText?.id != text.id) {
            app.pauseReadingTimer();
            final discard = await showConfirmDialog(context, title: '确认切换', content: '当前文章阅读未满30秒，未完成追踪。确定要放弃当前阅读记录吗？', confirmLabel: '放弃');
            if (!discard) {
              app.resumeReadingTimer();
              return;
            }
            app.discardCurrentReading();
          }
          if (!app.loadTextForReading(text.id)) {
            if (!context.mounted) return;
            await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('无法打开'),
                content: const Text('无法加载文本，请检查后重试'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('确定'),
                  ),
                ],
              ),
            );
            return;
          }
        },
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: context.cardPaddingH,
              vertical: context.cardPaddingV),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text.title,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis),
                    SizedBox(height: context.gapTiny),
                    Text('${text.author} · ${text.dynasty}',
                        style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              Text('${(text.averageDifficulty * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
