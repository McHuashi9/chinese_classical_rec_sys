import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

class ReadPage extends StatefulWidget {
  const ReadPage({super.key});

  @override
  State<ReadPage> createState() => _ReadPageState();
}

class _ReadPageState extends State<ReadPage> {
  final _focusNode = FocusNode();
  bool _needsPaginate = true;
  Size _frameSize = Size.zero;
  AppState? _app;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final app = context.read<AppState>();
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        app.prevPage();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        app.nextPage();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final text = context.select((AppState a) => a.readingText);
    final isDark = context.select((AppState a) => a.darkMode);
    final pages = context.select((AppState a) => a.pages);
    final currentPage = context.select((AppState a) => a.currentPage);
    final totalPages = context.select((AppState a) => a.totalPages);
    final timer = context.select((AppState a) => a.formattedReadingTime);

    if (text == null) {
      return const Center(child: Text('请从文库选择一篇古文'));
    }

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text.title,
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text('${text.author} · ${text.dynasty}',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Expanded(child: _buildReadingFrame(context, isDark, pages, currentPage)),
            const SizedBox(height: 12),
            _buildNavigationBar(context, isDark, pages, currentPage, totalPages, timer),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingFrame(
    BuildContext context,
    bool isDark,
    List<String> pages,
    int currentPage,
  ) {
    final bgColor = isDark ? AppTheme.darkCard : AppTheme.cardBg;

    if (_needsPaginate && context.read<AppState>().readingText != null) {
      _needsPaginate = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _doPaginate());
    }

    return LayoutBuilder(
      builder: (ctx, constraints) {
        if (constraints.biggest != _frameSize && constraints.biggest != Size.zero) {
          _frameSize = constraints.biggest;
          WidgetsBinding.instance.addPostFrameCallback((_) => _doPaginate());
        }

        final current = pages.isNotEmpty ? pages[currentPage] : '';
        final textColor = isDark ? AppTheme.darkInk : AppTheme.ink;

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
                      style: AppTheme.bodyReading,
                      maxWidth: constraints.maxWidth - 32,
                      lineColor: isDark
                          ? AppTheme.borderLight.withAlpha(60)
                          : AppTheme.borderLight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        height: double.infinity,
                        child: Text(
                          current,
                          style: AppTheme.bodyReading.copyWith(color: textColor),
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
    if (_app == null || _app!.readingText == null || _frameSize == Size.zero) return;
    final innerWidth = (_frameSize.width - 32).clamp(100.0, double.infinity);
    final innerHeight = (_frameSize.height - 32).clamp(50.0, double.infinity);
    if (innerWidth > 0 && innerHeight > 0) {
      _app!.paginate(innerWidth, innerHeight);
    }
  }

  Widget _buildNavigationBar(
    BuildContext context,
    bool isDark,
    List<String> pages,
    int currentPage,
    int totalPages,
    String timer,
  ) {
    final hasPrev = currentPage > 0;
    final hasNext = currentPage < totalPages - 1;

    return SizedBox(
      height: 36,
      child: Row(
        children: [
          TextButton(
            onPressed: hasPrev
                ? () => context.read<AppState>().prevPage()
                : null,
            child: const Text('◀ 上一页'),
          ),
          const Spacer(),
          Text(
            timer,
            style: TextStyle(
              fontSize: 16,
              fontFamily: AppTheme.fontUI,
              color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: hasNext
                ? () => context.read<AppState>().nextPage()
                : null,
            child: const Text('下一页 ▶'),
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

  _TextRuledPainter({
    required this.content,
    required this.style,
    required this.maxWidth,
    required this.lineColor,
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

    const padding = 16.0;

    for (final line in metrics) {
      final y = padding + line.baseline;
      canvas.drawLine(Offset(padding, y), Offset(size.width - padding, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TextRuledPainter oldDelegate) =>
      oldDelegate.content != content ||
      oldDelegate.maxWidth != maxWidth ||
      oldDelegate.lineColor != lineColor;
}
