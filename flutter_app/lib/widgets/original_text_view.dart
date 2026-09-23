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

/// 只读原文视图：供答题页「原文」用途内嵌使用（不再是独立路由）。
///
/// 会话语义（与旧 ReadingPreviewPage 一致）：
/// - [activeController] 非空且确为该篇活动会话：复用同一 ReadingController
///   （分页/滚动/计时连续，本组件不 dispose）；
/// - 为空：本地临时 ReadingController，`autoStart: false` **不计时、不结算**，
///   组件销毁即释放。
///
/// 防火墙语义：底部一律走“返回”（`alreadyTracked: true`），
/// ReadingFrame 的完成/放弃/退出回调全部缴械，交给 [onExit]。
/// 因此本视图无法触发阅读结算，不会与答题提交的结算路径打架。
class OriginalTextView extends StatefulWidget {
  /// 要展示的文章 id。
  final int textId;

  /// 活动阅读会话；null 表示只读快照。
  final ReadingController? activeController;

  /// 用户点“返回”时回调（内嵌场景由答题页切回题目视图）。
  final VoidCallback onExit;

  const OriginalTextView({
    super.key,
    required this.textId,
    required this.onExit,
    this.activeController,
  });

  @override
  State<OriginalTextView> createState() => _OriginalTextViewState();
}

class _OriginalTextViewState extends State<OriginalTextView> {
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
    // 此处直接赋值：didChangeDependencies 之后必然跟着 build，无需 setState
    // （在依赖变更阶段调 setState 会触发多余构建）。
    _text = coord.getTextDetail(widget.textId);

    if (_isActive) {
      final active = widget.activeController!;
      if (active.readingText != null) {
        _text = active.readingText;
        _annotations = active.annotations;
      }
    } else {
      if (_text == null) return;
      _annotations =
          AnnotationParser.parse(coord.getAnnotations(widget.textId));
      _translation = coord.getTranslation(widget.textId);
      _localController = ReadingController(ReadTracker());
      _localController!.loadText(
        _text!,
        annotations: _annotations,
        translation: _translation,
        showTranslation: context.read<SettingsController>().showTranslation,
        // 只读快照不计时。
        autoStart: false,
      );
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
    final text = _text;
    if (controller == null || text == null) {
      return const Center(child: Text('文章加载失败，请重试'));
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final settingsCtrl = context.watch<SettingsController>();
        final isDark = settingsCtrl.darkMode;
        final fontScale = settingsCtrl.fontScale;

        return SafeArea(
          child: ReadingFrame(
            viewData: ReadingViewData(
              text: text,
              pages: controller.pages,
              currentPage: controller.currentPage,
              totalPages: controller.totalPages,
              formattedTime: controller.formattedReadingTime,
              isDark: isDark,
              elapsedSeconds: controller.elapsedSeconds,
              // 只读语义：底部只出现“返回”，不出现完成/放弃。
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
              // 三个结算入口统一缴械为“返回”。
              onComplete: widget.onExit,
              onAbandon: widget.onExit,
              onExit: widget.onExit,
            ),
          ),
        );
      },
    );
  }
}
