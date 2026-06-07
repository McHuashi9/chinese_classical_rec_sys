import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/engine/annotation_parser.dart';

class AnnotationPopup extends StatelessWidget {
  final int number;
  final String text;
  final VoidCallback onDismiss;
  final double fontScale;
  final bool isDark;
  final Offset markerCenterGlobal;

  const AnnotationPopup({
    super.key,
    required this.number,
    required this.text,
    required this.onDismiss,
    required this.fontScale,
    required this.isDark,
    required this.markerCenterGlobal,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? AppTheme.darkCard : AppTheme.cardBg;
    final textColor = isDark ? AppTheme.darkInk : AppTheme.ink;
    final secondaryColor =
        isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary;
    final accentColor = isDark ? AppTheme.darkVermilion : AppTheme.vermilion;
    final screenSize =
        AppTheme.screenSizeForWidth(MediaQuery.sizeOf(context).width);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final parsed = AnnotationParser.parseEntry(text);
    final content = parsed.content.isNotEmpty ? parsed.content : text;

    return LayoutBuilder(
      builder: (context, constraints) {
        final overlayWidth = constraints.maxWidth;
        final overlayHeight = constraints.maxHeight;
        const maxPopupWidth = 480.0;
        const margin = 16.0;
        final popupWidth = overlayWidth < maxPopupWidth + margin * 2
            ? overlayWidth - margin * 2
            : maxPopupWidth;

        double left = markerCenterGlobal.dx - popupWidth / 2;
        left = left.clamp(margin, overlayWidth - popupWidth - margin);

        final bodyFontSize =
            AppTheme.bodyReadingSize(screenSize, fontScale).fontSize ?? 16;
        final lineCount = (text.length / 30).ceil().clamp(1, 200);
        final estimatedHeight =
            (lineCount * bodyFontSize * 1.7 + 80).clamp(120.0, screenHeight * 0.6);

        double top = markerCenterGlobal.dy + 4;
        if (top + estimatedHeight + margin > overlayHeight) {
          top = markerCenterGlobal.dy - 4 - estimatedHeight;
        }
        top = top.clamp(margin, overlayHeight - margin - 60);

        return Stack(
          children: [
            GestureDetector(
              onTap: onDismiss,
              child: Container(
                  width: overlayWidth,
                  height: overlayHeight,
                  color: Colors.transparent),
            ),
            Positioned(
              left: left,
              top: top,
              width: popupWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: overlayHeight * 0.6),
                child: Material(
                  elevation: 12,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: accentColor.withAlpha(60),
                        width: 1,
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (parsed.headword.isNotEmpty)
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          parsed.headword,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: bodyFontSize,
                                            fontWeight: FontWeight.w600,
                                            color: accentColor,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '〔$number〕',
                                        style: TextStyle(
                                          fontSize: 11 * fontScale,
                                          color: secondaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Text(
                                  '注释 [$number]',
                                  style: TextStyle(
                                    fontSize: 12 * fontScale,
                                    color: accentColor,
                                  ),
                                ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: onDismiss,
                                child: Icon(
                                  Icons.close,
                                  size: 18 * fontScale,
                                  color: secondaryColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          SelectableText(
                            content,
                            style: TextStyle(
                              fontFamily: AppTheme.fontBody,
                              fontSize: bodyFontSize,
                              height: 1.7,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static OverlayEntry show(
    BuildContext context,
    int number,
    String text, {
    VoidCallback? onDismissed,
    required double fontScale,
    required bool isDark,
    required Offset markerCenterGlobal,
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
        fontScale: fontScale,
        isDark: isDark,
        markerCenterGlobal: markerCenterGlobal,
      ),
    );
    Overlay.of(context).insert(entry);
    return entry;
  }
}
