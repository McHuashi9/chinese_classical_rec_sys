import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';

class ReadingViewData {
  final ChineseText text;
  final List<String> pages;
  final int currentPage;
  final int totalPages;
  final String formattedTime;
  final bool isDark;
  final int elapsedSeconds;
  final bool alreadyTracked;
  final Map<int, String> annotations;
  final bool showTranslation;

  /// 每页是否从译文段中间开始（译文交错分页边界样式用）。
  /// 非译文模式/未提供时按 false 处理。
  final List<bool>? pageStartsInTranslation;

  /// 仍在等待达标阅读的篇目 id（初始化引导用）。
  /// 非空时底栏倒计时带「还需阅读」措辞，让用户知道当前是在等阅读时长。
  final List<int> pendingReadTextIds;

  final VoidCallback onToggleTranslation;
  final void Function(int innerWidth, int innerHeight) onPaginate;
  final VoidCallback onNextPage;
  final VoidCallback onPrevPage;
  final VoidCallback onComplete;
  final VoidCallback onAbandon;
  final VoidCallback onExit;

  const ReadingViewData({
    required this.text,
    required this.pages,
    required this.currentPage,
    required this.totalPages,
    required this.formattedTime,
    required this.isDark,
    required this.elapsedSeconds,
    required this.alreadyTracked,
    required this.annotations,
    required this.showTranslation,
    this.pageStartsInTranslation,
    this.pendingReadTextIds = const [],
    required this.onToggleTranslation,
    required this.onPaginate,
    required this.onNextPage,
    required this.onPrevPage,
    required this.onComplete,
    required this.onAbandon,
    required this.onExit,
  });
}
