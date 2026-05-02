import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

class LibraryCard extends StatelessWidget {
  final ChineseText text;

  const LibraryCard({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: () {
          context.read<AppState>().loadTextForReading(text.id);
        },
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontFamily: AppTheme.fontTitle,
                        color:
                            theme.textTheme.titleLarge?.color ?? AppTheme.ink,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${text.author} · ${text.dynasty}',
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: AppTheme.fontBody,
                        color: theme.textTheme.bodyMedium?.color ??
                            AppTheme.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(text.averageDifficulty * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: AppTheme.fontUI,
                  color: AppTheme.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
