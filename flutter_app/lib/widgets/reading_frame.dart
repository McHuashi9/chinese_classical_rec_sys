import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/models/reading_view_data.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/engine/annotation_parser.dart';
import 'package:chinese_classical_rec_sys/widgets/annotation_popup.dart';

class ReadingFrame extends StatefulWidget {
  final ReadingViewData viewData;

  const ReadingFrame({
    super.key,
    required this.viewData,
  });

  @override
  State<ReadingFrame> createState() => _ReadingFrameState();
}

class _ReadingFrameState extends State<ReadingFrame> {
  final _focusNode = FocusNode();
  bool _needsPaginate = true;
  Size _frameSize = Size.zero;
  double _framePadding = 16;
  double _lastFontScale = 1.0;
  final _textKey = GlobalKey();
  OverlayEntry? _annotationOverlay;
  int? _currentAnnotationNumber;

  @override
  void dispose() {
    _dismissAnnotation();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ReadingFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewData.currentPage != widget.viewData.currentPage) {
      _dismissAnnotation();
    }
  }

  void _dismissAnnotation() {
    _annotationOverlay?.remove();
    _annotationOverlay = null;
    _currentAnnotationNumber = null;
  }

  void _showAnnotation(int number, {required Offset markerCenterGlobal}) {
    final text = widget.viewData.annotations[number];
    if (text == null || text.isEmpty) return;
    final fontScale = context.read<SettingsController>().fontScale;
    _currentAnnotationNumber = number;
    _annotationOverlay = AnnotationPopup.show(
      context, number, text,
      fontScale: fontScale,
      isDark: widget.viewData.isDark,
      markerCenterGlobal: markerCenterGlobal,
      onDismissed: () {
        _annotationOverlay = null;
        _currentAnnotationNumber = null;
      },
    );
  }

  void _handleTextTap(TapUpDetails details) {
    final current = widget.viewData.pages.isNotEmpty ? widget.viewData.pages[widget.viewData.currentPage] : '';
    if (current.isEmpty) return;

    final renderParagraph = _textKey.currentContext?.findRenderObject();
    if (renderParagraph is! RenderParagraph) return;

    final localPos = renderParagraph.globalToLocal(details.globalPosition);

    if (localPos.dx < 0 || localPos.dx > renderParagraph.size.width ||
        localPos.dy < 0 || localPos.dy > renderParagraph.size.height) {
      return;
    }

    final textPos = renderParagraph.getPositionForOffset(localPos);
    final num = AnnotatedTextBuilder.findAnnotationAtOffset(
      current, textPos.offset, widget.viewData.annotations,
    );

    if (num == null) {
      _dismissAnnotation();
      return;
    }

    if (_annotationOverlay != null) {
      if (num == _currentAnnotationNumber) {
        _dismissAnnotation();
        return;
      }
      _dismissAnnotation();
    }

    final markerSel = AnnotatedTextBuilder.markerSelection(current, num);
    final boxes = renderParagraph.getBoxesForSelection(markerSel);
    if (boxes.isEmpty) return;
    final markerRect = boxes.first.toRect();
    if (!markerRect.inflate(8).contains(localPos)) return;

    final markerCenterGlobal = renderParagraph.localToGlobal(
      Offset(markerRect.center.dx, markerRect.bottom),
    );

    _showAnnotation(num, markerCenterGlobal: markerCenterGlobal);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (widget.viewData.currentPage > 0) {
          widget.viewData.onPrevPage();
        } else {
          _boundaryFeedback('已到首页');
        }
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (widget.viewData.currentPage < widget.viewData.totalPages - 1) {
          widget.viewData.onNextPage();
        } else {
          _boundaryFeedback('已到末页');
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _boundaryFeedback(String message) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.maybeOf(context)
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        duration: const Duration(milliseconds: 600),
        width: 180,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final fontScale = context.select((SettingsController s) => s.fontScale);
    if (fontScale != _lastFontScale) {
      _lastFontScale = fontScale;
      _needsPaginate = true;
    }

    if (widget.viewData.pages.isEmpty) {
      _needsPaginate = true;
    }

    final framePadding = context.framePadding;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: context.pagePadding,
            vertical: context.gapLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.viewData.text.title,
                style: Theme.of(context).textTheme.headlineMedium,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
            ),
            SizedBox(height: context.gapSmall),
            Text('${widget.viewData.text.author} · ${widget.viewData.text.dynasty}',
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
                maxLines: 1),
            SizedBox(height: context.gapLg),
            Expanded(
                child: _buildReadingFrame(context, framePadding, fontScale)),
            SizedBox(height: context.cardPaddingV),
            _buildNavigationBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingFrame(BuildContext context, double framePadding, double fontScale) {
    final bgColor = widget.viewData.isDark ? AppTheme.darkCard : AppTheme.cardBg;
    final bodyStyle = AppTheme.bodyReadingSize(
        AppTheme.screenSizeForWidth(MediaQuery.sizeOf(context).width),
        fontScale);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final needsIt = (_needsPaginate && widget.viewData.pages.isEmpty)
            || (constraints.biggest != _frameSize && constraints.biggest != Size.zero);
        if (needsIt) {
          _needsPaginate = false;
          _frameSize = constraints.biggest;
          _framePadding = framePadding;
          WidgetsBinding.instance.addPostFrameCallback((_) => _doPaginate());
        }

        final current = widget.viewData.pages.isNotEmpty ? widget.viewData.pages[widget.viewData.currentPage] : '';
        final textColor = widget.viewData.isDark ? AppTheme.darkInk : AppTheme.ink;

        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: AppTheme.border, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: current.isNotEmpty
                ? GestureDetector(
                    onTapUp: _handleTextTap,
                    child: CustomPaint(
                      painter: _TextRuledPainter(
                        content: current,
                        style: bodyStyle,
                        maxWidth: constraints.maxWidth - framePadding * 2,
                        lineColor: widget.viewData.isDark
                            ? AppTheme.borderLight.withAlpha(60)
                            : AppTheme.borderLight,
                        padding: framePadding,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(framePadding),
                        child: SizedBox(
                          width: double.infinity,
                          height: double.infinity,
                          child: Text.rich(
                            AnnotatedTextBuilder.build(
                              current, widget.viewData.annotations,
                              bodyStyle.copyWith(color: textColor),
                            ),
                            key: _textKey,
                          ),
                        ),
                      ),
                    ),
                  )
                : const Center(child: Text('暂无内容')),
          ),
        );
      },
    );
  }

  void _doPaginate() {
    if (_frameSize.width <= 0 || _frameSize.height <= 0) return;
    final pad2 = _framePadding * 2;
    final innerWidth = (_frameSize.width - pad2).clamp(100.0, double.infinity);
    final innerHeight = (_frameSize.height - pad2).clamp(50.0, double.infinity);
    if (innerWidth > 0 && innerHeight > 0) {
      widget.viewData.onPaginate(innerWidth.toInt(), innerHeight.toInt());
    }
  }

  Widget _buildNavigationBar(BuildContext context) {
    final hasPrev = widget.viewData.currentPage > 0;
    final hasNext = widget.viewData.currentPage < widget.viewData.totalPages - 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (!widget.viewData.alreadyTracked)
          TextButton(
            onPressed: widget.viewData.onAbandon,
            child: Text('放弃',
                style: TextStyle(color: widget.viewData.isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary)),
          ),
        TextButton(
          onPressed: hasPrev ? widget.viewData.onPrevPage : null,
          child: const Text('◀ 上一页'),
        ),
        Text(
          widget.viewData.formattedTime,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: widget.viewData.isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
          ),
        ),
        TextButton(
          onPressed: hasNext ? widget.viewData.onNextPage : null,
          child: const Text('下一页 ▶'),
        ),
        if (widget.viewData.alreadyTracked)
          TextButton(
            onPressed: widget.viewData.onExit,
            child: const Text('返回'),
          )
        else
          TextButton(
            onPressed: widget.viewData.elapsedSeconds >= 30 ? widget.viewData.onComplete : null,
            child: Text(widget.viewData.elapsedSeconds >= 30 ? '完成' : '${30 - widget.viewData.elapsedSeconds}s'),
          ),
      ],
    );
  }
}

class _TextRuledPainter extends CustomPainter {
  final String content;
  final TextStyle style;
  final double maxWidth;
  final Color lineColor;
  final double padding;

  _TextRuledPainter({
    required this.content,
    required this.style,
    required this.maxWidth,
    required this.lineColor,
    required this.padding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (content.isEmpty) return;

    final tp = TextPainter(
      text: TextSpan(text: content, style: style),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: maxWidth);
    final metrics = tp.computeLineMetrics();

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0;

    for (final line in metrics) {
      if (line.width == 0) continue;
      final y = padding + line.baseline;
      canvas.drawLine(Offset(padding, y), Offset(size.width - padding, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TextRuledPainter oldDelegate) =>
      oldDelegate.content != content ||
      oldDelegate.maxWidth != maxWidth ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.padding != padding ||
      oldDelegate.style != style;
}
