import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

class TextCard extends StatelessWidget {
  const TextCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.cardPaddingH,
            vertical: context.cardPaddingV,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      SizedBox(height: context.gapTiny),
                      Text(subtitle!,
                          style: theme.textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
