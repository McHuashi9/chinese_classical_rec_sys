import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/models/reading_view_data.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/engine/algorithm_constants.dart';
import 'package:chinese_classical_rec_sys/engine/annotation_parser.dart';
import 'package:chinese_classical_rec_sys/widgets/annotation_popup.dart';

class ReadingFrame extends StatefulWidget {
  final ReadingViewData viewData;

  /// 供外部（如初始化教程）定位正文/注释标记的可选 Key。
  final GlobalKey? textKey;

  /// 供外部定位“译文对照”按钮的可选 Key。
  final GlobalKey? translationButtonKey;

  /// 供外部定位“下一页”按钮的可选 Key。
  final GlobalKey? nextPageButtonKey;

  /// 供外部定位“做题”按钮的可选 Key（F1 初始化教程第 4 步用）。
  final GlobalKey? quizButtonKey;

  /// 非空时在底部工具栏显示“做题”按钮（有题才由调用方传入）。
  final VoidCallback? onStartQuiz;

  const ReadingFrame({
    super.key,
    required this.viewData,
    this.textKey,
    this.translationButtonKey,
    this.nextPageButtonKey,
    this.quizButtonKey,
    this.onStartQuiz,
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

  GlobalKey get _effectiveTextKey => widget.textKey ?? _textKey;
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
    if (oldWidget.viewData.showTranslation != widget.viewData.showTranslation) {
      _needsPaginate = true;
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
      context,
      number,
      text,
      fontScale: fontScale,
      markerCenterGlobal: markerCenterGlobal,
      onDismissed: () {
        _annotationOverlay = null;
        _currentAnnotationNumber = null;
      },
    );
  }

  void _handleTextTap(TapUpDetails details) {
    final current = widget.viewData.pages.isNotEmpty
        ? widget.viewData.pages[widget.viewData.currentPage]
        : '';
    if (current.isEmpty) return;

    final renderParagraph = _effectiveTextKey.currentContext?.findRenderObject();
    if (renderParagraph is! RenderParagraph) return;

    final localPos = renderParagraph.globalToLocal(details.globalPosition);

    if (localPos.dx < 0 ||
        localPos.dx > renderParagraph.size.width ||
        localPos.dy < 0 ||
        localPos.dy > renderParagraph.size.height) {
      return;
    }

    final textPos = renderParagraph.getPositionForOffset(localPos);
    // 译文模式零宽标记不参与排版：先映射回原始页串偏移再定位注释标记。
    final rawOffset =
        AnnotatedTextBuilder.paintedToRawOffset(current, textPos.offset);
    final num = AnnotatedTextBuilder.findAnnotationAtOffset(
      current,
      rawOffset,
      widget.viewData.annotations,
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
    final showRuledLines =
        context.select((SettingsController s) => s.showRuledLines);
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
            horizontal: context.pagePadding, vertical: context.gapLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.viewData.text.title,
              style: Theme.of(context).textTheme.headlineMedium,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            SizedBox(height: context.gapSmall),
            Text(
                '${widget.viewData.text.author} · ${widget.viewData.text.dynasty}',
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
                maxLines: 1),
            SizedBox(height: context.gapLg),
            Expanded(
                child: _buildReadingFrame(
                    context, framePadding, fontScale, showRuledLines)),
            SizedBox(height: context.cardPaddingV),
            _buildNavigationBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingFrame(BuildContext context, double framePadding,
      double fontScale, bool showRuledLines) {
    final bgColor = context.appColors.cardBg;
    final bodyStyle = AppTheme.bodyReadingSize(
        AppTheme.screenSizeForWidth(MediaQuery.sizeOf(context).width),
        fontScale);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final needsIt = _needsPaginate ||
            (constraints.biggest != _frameSize &&
                constraints.biggest != Size.zero);
        if (needsIt) {
          _needsPaginate = false;
          _frameSize = constraints.biggest;
          _framePadding = framePadding;
          WidgetsBinding.instance.addPostFrameCallback((_) => _doPaginate());
        }

        final current = widget.viewData.pages.isNotEmpty
            ? widget.viewData.pages[widget.viewData.currentPage]
            : '';
        final textColor = context.appColors.ink;
        final pageStarts = widget.viewData.pageStartsInTranslation;
        final translationActive = pageStarts != null &&
                pageStarts.length > widget.viewData.currentPage
            ? pageStarts[widget.viewData.currentPage]
            : false;
        final textSpan = AnnotatedTextBuilder.build(
          current,
          widget.viewData.annotations,
          bodyStyle.copyWith(color: textColor),
          isDark: widget.viewData.isDark,
          accentColor: Theme.of(ctx).colorScheme.primary,
          translationActive: translationActive,
        );

        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: context.appColors.border, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: current.isNotEmpty
                ? GestureDetector(
                    onTapUp: _handleTextTap,
                    child: CustomPaint(
                      painter: showRuledLines
                          ? _TextRuledPainter(
                              textSpan: textSpan,
                              maxWidth: constraints.maxWidth - framePadding * 2,
                              lineColor: widget.viewData.isDark
                                  ? context.appColors.borderLight.withAlpha(60)
                                  : context.appColors.borderLight,
                              padding: framePadding,
                            )
                          : null,
                      child: Padding(
                        padding: EdgeInsets.all(framePadding),
                        child: SizedBox(
                          width: double.infinity,
                          height: double.infinity,
                          child: Text.rich(
                            textSpan,
                            key: _effectiveTextKey,
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
    final hasNext =
        widget.viewData.currentPage < widget.viewData.totalPages - 1;
    final minReadTime = minReadTimeSeconds(widget.viewData.text.charCount);
    final canComplete = widget.viewData.elapsedSeconds >= minReadTime;
    final pageLabel =
        '第 ${widget.viewData.currentPage + 1} / ${widget.viewData.totalPages} 页';
    final progress = widget.viewData.totalPages <= 0
        ? 0.0
        : (widget.viewData.currentPage + 1) / widget.viewData.totalPages;
    final timerText = Text(
      widget.viewData.formattedTime,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: context.appColors.inkSecondary,
          ),
    );
    final translationButton = IconButton(
      key: widget.translationButtonKey,
      tooltip: '译文对照',
      onPressed: widget.viewData.onToggleTranslation,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        Icons.translate,
        size: 20,
        color: widget.viewData.showTranslation
            ? Theme.of(context).colorScheme.primary
            : context.appColors.inkSecondary,
      ),
    );
    final abandonButton = !widget.viewData.alreadyTracked
        ? TextButton(
            onPressed: widget.viewData.onAbandon,
            child: Text('放弃',
                style: TextStyle(color: context.appColors.inkSecondary)),
          )
        : null;
    final prevButton = TextButton(
      onPressed: hasPrev ? widget.viewData.onPrevPage : null,
      child: const Text('◀ 上一页'),
    );
    final nextButton = TextButton(
      key: widget.nextPageButtonKey,
      onPressed: hasNext ? widget.viewData.onNextPage : null,
      child: const Text('下一页 ▶'),
    );
    final finishButton = widget.viewData.alreadyTracked
        ? TextButton(
            onPressed: widget.viewData.onExit,
            child: const Text('返回'),
          )
        : TextButton(
            onPressed: canComplete ? widget.viewData.onComplete : null,
            child: Text(canComplete
                ? '完成'
                : '${(minReadTime - widget.viewData.elapsedSeconds).ceil()}s'),
          );
    final quizButton = widget.onStartQuiz == null
        ? null
        : TextButton.icon(
            key: widget.quizButtonKey,
            onPressed: widget.onStartQuiz,
            style: TextButton.styleFrom(
              foregroundColor: context.accent,
            ),
            icon: const Icon(Icons.edit_note, size: 18),
            label: const Text('做题'),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      pageLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: context.appColors.inkSecondary,
                          ),
                    ),
                  ),
                  timerText,
                ],
              ),
              SizedBox(height: context.gapSmall),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: context.appColors.borderLight.withAlpha(80),
                  valueColor: AlwaysStoppedAnimation(context.accent),
                ),
              ),
              SizedBox(height: context.gapSmall),
              // M3 F9 加入“做题”按钮时，直接追加到该 Wrap 即可，布局会自动换行。
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  translationButton,
                  if (quizButton != null) quizButton,
                  if (abandonButton != null) abandonButton,
                  prevButton,
                  nextButton,
                  finishButton,
                ],
              ),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            translationButton,
            if (quizButton != null) quizButton,
            if (abandonButton != null) abandonButton,
            prevButton,
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pageLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: context.appColors.inkSecondary,
                        ),
                  ),
                  const SizedBox(height: 2),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 2,
                      backgroundColor:
                          context.appColors.borderLight.withAlpha(80),
                      valueColor: AlwaysStoppedAnimation(context.accent),
                    ),
                  ),
                ],
              ),
            ),
            timerText,
            nextButton,
            finishButton,
          ],
        );
      },
    );
  }
}

class _TextRuledPainter extends CustomPainter {
  final TextSpan textSpan;
  final double maxWidth;
  final Color lineColor;
  final double padding;

  _TextRuledPainter({
    required this.textSpan,
    required this.maxWidth,
    required this.lineColor,
    required this.padding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (textSpan.toPlainText().isEmpty) return;

    final tp = TextPainter(
      text: textSpan,
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
      canvas.drawLine(
          Offset(padding, y), Offset(size.width - padding, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TextRuledPainter oldDelegate) =>
      oldDelegate.textSpan != textSpan ||
      oldDelegate.maxWidth != maxWidth ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.padding != padding;
}
