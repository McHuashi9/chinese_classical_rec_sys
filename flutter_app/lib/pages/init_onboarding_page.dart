import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/models/reading_view_data.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/pages/quiz_page.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/engine/annotation_parser.dart';
import 'package:chinese_classical_rec_sys/widgets/reading_frame.dart';

/// 强制初始化引导页：展示两篇初始化文章，全部阅读后可开始 6 道初始化题。
class InitOnboardingPage extends StatefulWidget {
  const InitOnboardingPage({super.key});

  @override
  State<InitOnboardingPage> createState() => _InitOnboardingPageState();
}

class _InitOnboardingPageState extends State<InitOnboardingPage> {
  @override
  Widget build(BuildContext context) {
    final coord = context.read<AppCoordinator>();
    final userCtrl = context.watch<UserController>();
    final isDark = context.select((SettingsController s) => s.darkMode);

    if (userCtrl.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('初始化完成')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle,
                    size: 64, color: AppTheme.stoneGreen),
                const SizedBox(height: 16),
                const Text('已完成初始化，可以开始学习了'),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('开始使用'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final texts = coord.getInitTexts();
    final allRead = texts.isNotEmpty &&
        texts.every((t) => coord.readTracker.isTextRead(t.id));

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.darkPaper : AppTheme.paper,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const SizedBox.shrink(),
          title: const Text('初始化引导'),
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(context.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '完成 6 道题后即可正常使用',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: context.gapMedium),
              Text(
                '请先阅读下面两篇短文（可查看注释与译文），然后完成 6 道随文题。'
                '初始化题不计入普通测验，也不会进入复习队列。',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(height: 1.6),
              ),
              SizedBox(height: context.gapLg),
              const Divider(color: AppTheme.border, height: 1),
              SizedBox(height: context.gapLg),
              for (final text in texts) ...[
                _InitArticleTile(
                    text: text, isRead: coord.readTracker.isTextRead(text.id)),
                SizedBox(height: context.gapSmall),
              ],
              SizedBox(height: context.gapXl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: context.accent,
                    foregroundColor: AppTheme.cardBg,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: allRead ? _startInitQuiz : null,
                  child: Text(allRead ? '开始 6 题初始化' : '请先阅读两篇文章'),
                ),
              ),
              SizedBox(height: context.gapXxl),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startInitQuiz() async {
    final userCtrl = context.read<UserController>();
    final questions = userCtrl.getInitQuestions();
    if (questions.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('初始化题目加载失败，请重试')),
        );
      }
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => QuizPage(
          articleTitle: '初始化测验',
          questions: questions,
          isInit: true,
        ),
      ),
    );
    if (!mounted) return;
    if (context.read<UserController>().isInitialized) {
      Navigator.of(context).pop();
    }
  }
}

class _InitArticleTile extends StatelessWidget {
  final ChineseText text;
  final bool isRead;

  const _InitArticleTile({required this.text, required this.isRead});

  @override
  Widget build(BuildContext context) {
    final coord = context.read<AppCoordinator>();
    return Card(
      child: ListTile(
        leading: Icon(
          isRead ? Icons.check_circle : Icons.menu_book,
          color: isRead ? AppTheme.stoneGreen : context.accent,
        ),
        title: Text(text.title),
        subtitle: Text(text.author.isEmpty
            ? text.dynasty
            : '${text.author} · ${text.dynasty}'),
        trailing: isRead
            ? const Text('已读')
            : FilledButton.tonal(
                onPressed: () {
                  // getInitTexts() 返回的是列表缓存（无正文），进入阅读前必须拉全文；
                  // 否则 ReadingFrame 会显示“暂无内容”。
                  final detail = coord.getTextDetail(text.id);
                  if (detail == null || detail.content.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('文章加载失败，请重试')),
                    );
                    return;
                  }
                  final raw = coord.getAnnotations(text.id);
                  final translation = coord.getTranslation(text.id);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => InitReadingPage(
                        text: detail,
                        annotations: AnnotationParser.parse(raw),
                        translation: translation,
                      ),
                    ),
                  );
                },
                child: const Text('阅读'),
              ),
      ),
    );
  }
}

/// 初始化阅读页：独立使用 [ReadingFrame]，退出时调用 [AppCoordinator.recordInitRead]。
class InitReadingPage extends StatefulWidget {
  final ChineseText text;
  final Map<int, String> annotations;
  final String translation;

  const InitReadingPage({
    super.key,
    required this.text,
    required this.annotations,
    required this.translation,
  });

  @override
  State<InitReadingPage> createState() => _InitReadingPageState();
}

class _InitReadingPageState extends State<InitReadingPage> {
  late final ReadingController _readingCtrl;
  bool _recorded = false;

  @override
  void initState() {
    super.initState();
    _readingCtrl = ReadingController(ReadTracker());
    _readingCtrl.loadText(
      widget.text,
      annotations: widget.annotations,
      translation: widget.translation,
      showTranslation: context.read<SettingsController>().showTranslation,
    );
  }

  @override
  void dispose() {
    _readingCtrl.dispose();
    super.dispose();
  }

  void _finish() {
    if (_recorded) return;
    _recorded = true;
    final coord = context.read<AppCoordinator>();
    coord.recordInitRead(
        widget.text.id, _readingCtrl.elapsedSeconds.toDouble());
    _readingCtrl.stopTimer();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _readingCtrl,
      builder: (context, _) {
        final settingsCtrl = context.watch<SettingsController>();
        final isDark = settingsCtrl.darkMode;
        final fontScale = settingsCtrl.fontScale;
        final pages = _readingCtrl.pages;
        final currentPage = _readingCtrl.currentPage;
        final totalPages = _readingCtrl.totalPages;

        return Scaffold(
          backgroundColor: isDark ? AppTheme.darkPaper : AppTheme.paper,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back,
                  color: isDark ? AppTheme.darkInk : AppTheme.ink),
              onPressed: _finish,
            ),
            title: Text(widget.text.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFamily: AppTheme.fontTitle,
                    )),
          ),
          body: SafeArea(
            child: ReadingFrame(
              viewData: ReadingViewData(
                text: widget.text,
                pages: pages,
                currentPage: currentPage,
                totalPages: totalPages,
                formattedTime: _readingCtrl.formattedReadingTime,
                isDark: isDark,
                elapsedSeconds: _readingCtrl.elapsedSeconds,
                alreadyTracked: false,
                annotations: widget.annotations,
                showTranslation: _readingCtrl.showTranslation,
                pageStartsInTranslation: _readingCtrl.pageStartsInTranslation,
                onToggleTranslation: () => _readingCtrl
                    .setShowTranslation(!_readingCtrl.showTranslation),
                onPaginate: (w, h) => _readingCtrl.paginate(
                  w.toDouble(),
                  h.toDouble(),
                  AppTheme.screenSizeForWidth(MediaQuery.sizeOf(context).width),
                  fontScale,
                  isDark,
                  accentColor: context.accent,
                ),
                onNextPage: _readingCtrl.nextPage,
                onPrevPage: _readingCtrl.prevPage,
                onComplete: _finish,
                onAbandon: _finish,
                onExit: _finish,
              ),
            ),
          ),
        );
      },
    );
  }
}
