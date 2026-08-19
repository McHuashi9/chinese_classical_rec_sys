import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/engine/annotation_parser.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/models/reading_view_data.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/reading_frame.dart';

/// 原文预览页：供答题页“原文”按钮使用。
///
/// - [activeController] 非空：复用活动阅读会话（同一 ReadingController，计时继续，
///   不 dispose；通常从阅读中进入答题时使用）。
/// - [activeController] 为空：只读原文预览（本地临时 ReadingController，不计时、
///   不结算，退出即销毁）。
class ReadingPreviewPage extends StatefulWidget {
  final int textId;
  final ReadingController? activeController;

  const ReadingPreviewPage({
    super.key,
    required this.textId,
    this.activeController,
  });

  @override
  State<ReadingPreviewPage> createState() => _ReadingPreviewPageState();
}

class _ReadingPreviewPageState extends State<ReadingPreviewPage> {
  ReadingController? _localController;
  ChineseText? _text;
  Map<int, String> _annotations = const {};
  String _translation = '';
  bool _initialized = false;

  bool get _isActive => widget.activeController != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final coord = context.read<AppCoordinator>();
    final text = coord.getTextDetail(widget.textId);
    _text = text;

    if (!_isActive) {
      if (text == null) return;
      _annotations = AnnotationParser.parse(coord.getAnnotations(widget.textId));
      _translation = coord.getTranslation(widget.textId);
      _localController = ReadingController(ReadTracker());
      _localController!.loadText(
        text,
        annotations: _annotations,
        translation: _translation,
        showTranslation: context.read<SettingsController>().showTranslation,
        // 只读预览不计时。
        autoStart: false,
      );
    } else {
      final active = widget.activeController!;
      if (active.readingText != null) {
        _text = active.readingText;
        _annotations = active.annotations;
      }
    }
  }

  @override
  void dispose() {
    _localController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.activeController ?? _localController;
    if (controller == null || _text == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('原文')),
        body: const Center(child: Text('文章加载失败，请重试')),
      );
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final settingsCtrl = context.watch<SettingsController>();
        final isDark = settingsCtrl.darkMode;
        final fontScale = settingsCtrl.fontScale;
        final pages = controller.pages;
        final currentPage = controller.currentPage;
        final totalPages = controller.totalPages;

        return Scaffold(
          backgroundColor: context.appColors.paper,
          appBar: AppBar(
            // 合法例外：AppBar 透明背景以露出 Scaffold 纸色。
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: context.appColors.ink),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              '原文 · ${_text!.title}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontFamily: AppTheme.fontTitle,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: SafeArea(
            child: ReadingFrame(
              viewData: ReadingViewData(
                text: _text!,
                pages: pages,
                currentPage: currentPage,
                totalPages: totalPages,
                formattedTime: controller.formattedReadingTime,
                isDark: isDark,
                elapsedSeconds: controller.elapsedSeconds,
                // 预览/原文视图统一用“返回”语义，不显示完成/放弃。
                alreadyTracked: true,
                annotations: controller.annotations,
                showTranslation: controller.showTranslation,
                pageStartsInTranslation: controller.pageStartsInTranslation,
                onToggleTranslation: () =>
                    controller.setShowTranslation(!controller.showTranslation),
                onPaginate: (w, h) => controller.paginate(
                  w.toDouble(),
                  h.toDouble(),
                  AppTheme.screenSizeForWidth(MediaQuery.sizeOf(context).width),
                  fontScale,
                  isDark,
                  accentColor: context.accent,
                ),
                onNextPage: controller.nextPage,
                onPrevPage: controller.prevPage,
                onComplete: () => Navigator.of(context).pop(),
                onAbandon: () => Navigator.of(context).pop(),
                onExit: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        );
      },
    );
  }
}
