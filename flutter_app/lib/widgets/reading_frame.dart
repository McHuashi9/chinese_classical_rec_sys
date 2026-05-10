import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

class ReadingFrame extends StatefulWidget {
  final ChineseText text;
  final List<String> pages;
  final int currentPage;
  final int totalPages;
  final String formattedTime;
  final bool isDark;
  final int elapsedSeconds;
  final bool alreadyTracked;
  final void Function(int innerWidth, int innerHeight) onPaginate;
  final VoidCallback onNextPage;
  final VoidCallback onPrevPage;
  final VoidCallback onComplete;
  final VoidCallback onAbandon;
  final VoidCallback onExit;

  const ReadingFrame({
    super.key,
    required this.text,
    required this.pages,
    required this.currentPage,
    required this.totalPages,
    required this.formattedTime,
    required this.isDark,
    required this.elapsedSeconds,
    required this.alreadyTracked,
    required this.onPaginate,
    required this.onNextPage,
    required this.onPrevPage,
    required this.onComplete,
    required this.onAbandon,
    required this.onExit,
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

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        widget.onPrevPage();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        widget.onNextPage();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final fontScale = context.select((AppState a) => a.fontScale);
    if (fontScale != _lastFontScale) {
      _lastFontScale = fontScale;
      _needsPaginate = true;
    }

    if (widget.pages.isEmpty) {
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
            vertical: context.gapHuge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.text.title,
                style: Theme.of(context).textTheme.headlineMedium,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
            ),
            SizedBox(height: context.gapSmall),
            Text('${widget.text.author} · ${widget.text.dynasty}',
                style: Theme.of(context).textTheme.bodyMedium),
            SizedBox(height: context.gapHuge),
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
    final bgColor = widget.isDark ? AppTheme.darkCard : AppTheme.cardBg;
    final bodyStyle = AppTheme.bodyReadingSize(
        AppTheme.screenSizeForWidth(MediaQuery.sizeOf(context).width),
        fontScale);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final needsIt = (_needsPaginate && widget.pages.isEmpty)
            || (constraints.biggest != _frameSize && constraints.biggest != Size.zero);
        if (needsIt) {
          _needsPaginate = false;
          _frameSize = constraints.biggest;
          _framePadding = framePadding;
          WidgetsBinding.instance.addPostFrameCallback((_) => _doPaginate());
        }

        final current = widget.pages.isNotEmpty ? widget.pages[widget.currentPage] : '';
        final textColor = widget.isDark ? AppTheme.darkInk : AppTheme.ink;

        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: AppTheme.border, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: current.isNotEmpty
                ? CustomPaint(
                    painter: _TextRuledPainter(
                      content: current,
                      style: bodyStyle,
                      maxWidth: constraints.maxWidth - framePadding * 2,
                      lineColor: widget.isDark
                          ? AppTheme.borderLight.withAlpha(60)
                          : AppTheme.borderLight,
                      padding: framePadding,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(framePadding),
                      child: SizedBox(
                        width: double.infinity,
                        height: double.infinity,
                        child: Text(
                          current,
                          style: bodyStyle.copyWith(color: textColor),
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
      widget.onPaginate(innerWidth.toInt(), innerHeight.toInt());
    }
  }

  Widget _buildNavigationBar(BuildContext context) {
    final hasPrev = widget.currentPage > 0;
    final hasNext = widget.currentPage < widget.totalPages - 1;

    return SizedBox(
      height: 36,
      child: Row(
        children: [
          if (widget.alreadyTracked) const Spacer() else
          TextButton(
            onPressed: widget.onAbandon,
            child: Text('放弃',
                style: TextStyle(color: widget.isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary)),
          ),
          const Spacer(),
          TextButton(
            onPressed: hasPrev ? widget.onPrevPage : null,
            child: const Text('◀ 上一页'),
          ),
          const Spacer(),
          Text(
            widget.formattedTime,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: widget.isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: hasNext ? widget.onNextPage : null,
            child: const Text('下一页 ▶'),
          ),
          const Spacer(),
          if (widget.alreadyTracked)
            TextButton(
              onPressed: widget.onExit,
              child: const Text('返回'),
            )
          else
            TextButton(
              onPressed: widget.elapsedSeconds >= 30 ? widget.onComplete : null,
              child: Text(widget.elapsedSeconds >= 30 ? '完成' : '${30 - widget.elapsedSeconds}s'),
            ),
        ],
      ),
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
