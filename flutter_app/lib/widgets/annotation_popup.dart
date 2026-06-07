import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

class AnnotationPopup extends StatelessWidget {
  final int number;
  final String text;
  final VoidCallback onDismiss;

  const AnnotationPopup({
    super.key,
    required this.number,
    required this.text,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          GestureDetector(
            onTap: onDismiss,
            child: Container(color: Colors.transparent),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 480),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.vermilion.withAlpha(60),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.vermilion.withAlpha(30),
                              border: Border.all(
                                color: AppTheme.vermilion.withAlpha(120),
                                width: 1.2,
                              ),
                            ),
                            child: Text(
                              '$number',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.vermilion,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '注释',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.vermilion,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: onDismiss,
                            child: const Icon(
                              Icons.close,
                              size: 18,
                              color: AppTheme.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SelectableText(
                        text,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 16,
                          height: 1.7,
                          color: AppTheme.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static OverlayEntry show(
    BuildContext context,
    int number,
    String text, {
    VoidCallback? onDismissed,
  }) {
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => AnnotationPopup(
        number: number,
        text: text,
        onDismiss: () {
          entry.remove();
          onDismissed?.call();
        },
      ),
    );
    Overlay.of(context).insert(entry);
    return entry;
  }
}
