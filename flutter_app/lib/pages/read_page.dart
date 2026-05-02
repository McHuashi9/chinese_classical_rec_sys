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
  final _prevHover = ValueNotifier(false);
  final _nextHover = ValueNotifier(false);
  bool _needsPaginate = true;
  Size _frameSize = Size.zero;
  AppState? _app;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _app?.startReadingTimer();
    });
  }

  @override
  void dispose() {
    _app?.stopReadingTimer();
    _focusNode.dispose();
    _prevHover.dispose();
    _nextHover.dispose();
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
    final app = context.watch<AppState>();
    final text = app.readingText;

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
            Expanded(child: _buildReadingFrame(app)),
            const SizedBox(height: 12),
            _buildNavigationBar(app),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingFrame(AppState app) {
    final isDark = app.darkMode;
    final bgColor = isDark ? AppTheme.darkCard : AppTheme.cardBg;

    if (_needsPaginate && app.readingText != null) {
      _needsPaginate = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _doPaginate());
    }

    return LayoutBuilder(
      builder: (ctx, constraints) {
        if (constraints.biggest != _frameSize && constraints.biggest != Size.zero) {
          _frameSize = constraints.biggest;
          WidgetsBinding.instance.addPostFrameCallback((_) => _doPaginate());
        }

        final pages = app.pages;
        final current = pages.isNotEmpty ? pages[app.currentPage] : '';
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

  Widget _buildNavigationBar(AppState app) {
    final hasPrev = app.currentPage > 0;
    final hasNext = app.currentPage < app.totalPages - 1;
    final textColor =
        app.darkMode ? AppTheme.darkInkSecondary : AppTheme.inkSecondary;

    return SizedBox(
      height: 36,
      child: Row(
        children: [
          _buildNavButton(
            label: '◀ 上一页',
            enabled: hasPrev,
            onTap: () => app.prevPage(),
            textColor: textColor,
            hoverNotifier: _prevHover,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Center(
              child: Text(
                app.formattedReadingTime,
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: AppTheme.fontUI,
                  color: textColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          _buildNavButton(
            label: '下一页 ▶',
            enabled: hasNext,
            onTap: () => app.nextPage(),
            textColor: textColor,
            hoverNotifier: _nextHover,
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    required Color textColor,
    required ValueNotifier<bool> hoverNotifier,
  }) {
    return ValueListenableBuilder(
      valueListenable: hoverNotifier,
      builder: (_, hover, __) {
        return GestureDetector(
          onTap: enabled ? onTap : null,
          child: MouseRegion(
            onEnter: (_) => hoverNotifier.value = true,
            onExit: (_) => hoverNotifier.value = false,
            cursor:
                enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: Opacity(
              opacity: enabled ? 1.0 : 0.4,
              child: Container(
                width: 80,
                height: 36,
                decoration: BoxDecoration(
                  color: hover && enabled
                      ? AppTheme.borderLight
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: AppTheme.fontUI,
                    color: hover && enabled
                        ? AppTheme.vermilionHover
                        : textColor,
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
