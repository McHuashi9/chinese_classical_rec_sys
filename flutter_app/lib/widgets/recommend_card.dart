import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

class RecommendCard extends StatelessWidget {
  final RecommendResult result;

  const RecommendCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final prob = (result.probability * 100).toStringAsFixed(1);
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: () {
          context.read<AppState>().loadTextForReading(result.text.id);
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
                      result.text.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontFamily: AppTheme.fontTitle,
                        color: theme.textTheme.titleLarge?.color ?? AppTheme.ink,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${result.text.author} · ${result.text.dynasty}',
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
                '$prob%',
                style: const TextStyle(
                  fontSize: 16,
                  fontFamily: AppTheme.fontUI,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.vermilion,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
