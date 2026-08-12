import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:chinese_classical_rec_sys/engine/annotation_parser.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/engine/translation_builder.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

class ReadingController extends ChangeNotifier {
  final ReadTracker _readTracker;

  ChineseText? _readingText;
  List<String> _pages = [];
  int _currentPage = 0;
  int _elapsedSeconds = 0;
  Timer? _readingTimer;
  int? _readingTextId;
  Map<int, String> _annotations = {};
  String _interleavedText = '';
  bool _showTranslation = false;

  ReadingController(this._readTracker);

  ChineseText? get readingText => _readingText;
  List<String> get pages => _pages;
  int get currentPage => _currentPage;
  int get totalPages => _pages.isEmpty ? 0 : _pages.length;
  int get elapsedSeconds => _elapsedSeconds;
  bool get isReading => _readingText != null;
  int? get readingTextId => _readingTextId;
  Map<int, String> get annotations => _annotations;
  bool get showTranslation => _showTranslation;

  /// 阅读器内实时切换译文对照（不持久化，重分页由 ReadingFrame 检测）
  void setShowTranslation(bool value) {
    if (_showTranslation == value) return;
    _showTranslation = value;
    notifyListeners();
  }

  String get formattedReadingTime {
    final m = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get currentPageNumberLabel {
    if (_pages.isEmpty) return '';
    return '第 ${_currentPage + 1} / ${_pages.length} 页';
  }

  bool isTextRead(int textId) => _readTracker.isTextRead(textId);

  bool get hasUnrecordedReading =>
      _readTracker.hasUnrecordedReading(_readingTextId);

  bool loadText(ChineseText text,
      {Map<int, String> annotations = const {},
      String translation = '',
      bool showTranslation = false}) {
    final textId = text.id;

    if (_readingTextId != null) {
      _readTracker.saveDuration(_readingTextId!, _elapsedSeconds);
    }

    _readingTimer?.cancel();
    _readingTimer = null;

    _readingText = text;
    _readingTextId = textId;
    _currentPage = 0;
    _pages = [];
    _annotations = annotations;
    _interleavedText = translation.isEmpty
        ? text.content
        : TranslationBuilder.toInterleavedText(
            TranslationBuilder.buildInterleaved(text.content, translation));
    _showTranslation = showTranslation;

    _readTracker.ensureState(textId);
    _elapsedSeconds = 0;

    startTimer();
    notifyListeners();
    return true;
  }

  void paginate(double pageWidth, double pageHeight, ScreenSize screenSize,
      double fontScale, bool isDark) {
    if (_readingText == null) return;
    final content = _showTranslation ? _interleavedText : _readingText!.content;
    if (content.isEmpty) {
      _pages = [];
      return;
    }

    final bodyStyle = AppTheme.bodyReadingSize(screenSize, fontScale);
    final tp = TextPainter(
      text: AnnotatedTextBuilder.build(
          content, _annotations, bodyStyle, isDark: isDark),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: pageWidth);
    final lineMetrics = tp.computeLineMetrics();

    final lineHeight = (bodyStyle.fontSize ?? 16.0) * (bodyStyle.height ?? 1.8);
    final linesPerPage = (pageHeight / lineHeight).floor();
    if (linesPerPage <= 0 || lineMetrics.isEmpty) {
      _pages = [content];
      _currentPage = 0;
      notifyListeners();
      return;
    }

    _pages = _splitIntoPages(tp, lineMetrics, linesPerPage, content);
    _currentPage = _currentPage.clamp(0, _pages.length - 1);
    notifyListeners();
  }

  void nextPage() {
    if (_currentPage < _pages.length - 1) {
      _currentPage++;
      notifyListeners();
    }
  }

  void prevPage() {
    if (_currentPage > 0) {
      _currentPage--;
      notifyListeners();
    }
  }

  void startTimer() {
    if (_readingTimer != null) return;
    _readingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedSeconds++;
      notifyListeners();
    });
  }

  void stopTimer() {
    _readingTimer?.cancel();
    _readingTimer = null;

    if (_readingTextId == null) return;

    _readTracker.saveDuration(_readingTextId!, _elapsedSeconds);
  }

  void pauseTimer() {
    _readingTimer?.cancel();
    _readingTimer = null;
  }

  void resumeTimer() {
    if (_readingTimer != null) return;
    _readingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedSeconds++;
      notifyListeners();
    });
  }

  void discardReading() {
    _readingText = null;
    _readingTextId = null;
    _pages = [];
    _currentPage = 0;
    _elapsedSeconds = 0;
    _annotations = {};
    _interleavedText = '';
    _showTranslation = false;
    _readingTimer?.cancel();
    _readingTimer = null;
    notifyListeners();
  }

  List<String> _splitIntoPages(
    TextPainter tp,
    List<LineMetrics> lineMetrics,
    int linesPerPage,
    String content,
  ) {
    final result = <String>[];
    for (int startLine = 0; startLine < lineMetrics.length; startLine += linesPerPage) {
      final startOffset = startLine == 0
          ? 0
          : _getLineStartOffset(tp, lineMetrics, startLine);
      final endLine = (startLine + linesPerPage - 1).clamp(0, lineMetrics.length - 1);
      final endOffset = tp.getPositionForOffset(
        Offset(tp.width, lineMetrics[endLine].baseline),
      ).offset;
      result.add(content.substring(startOffset, endOffset).trimRight());
    }
    return result;
  }

  int _getLineStartOffset(
    TextPainter tp,
    List<LineMetrics> lineMetrics,
    int lineIndex,
  ) {
    if (lineIndex <= 0) return 0;
    final pos = tp.getPositionForOffset(
      Offset(0, lineMetrics[lineIndex].baseline),
    );
    return pos.offset;
  }

  @override
  void dispose() {
    _readingTimer?.cancel();
    super.dispose();
  }
}
