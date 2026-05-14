import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/widgets/dialogs.dart';

class ArticleDetailPage extends StatelessWidget {
  final int textId;

  const ArticleDetailPage({super.key, required this.textId});

  double _estimatedMinutes(int charCount) {
    const vMax = 150;
    final minutes = charCount / vMax;
    return minutes < 1.0 ? 1.0 : double.parse(minutes.toStringAsFixed(1));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final text = app.getTextDetail(textId);
    if (text == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('文章未找到')),
        body: const Center(child: Text('无法加载文章信息')),
      );
    }

    final isDark = app.darkMode;
    final estMinutes = _estimatedMinutes(text.charCount);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkPaper : AppTheme.paper,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? AppTheme.darkInk : AppTheme.ink,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(context.pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text.title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontFamily: AppTheme.fontTitle,
              ),
            ),
            SizedBox(height: context.gapSmall),
            Text(
              '${text.author} · ${text.dynasty}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
              ),
            ),
            if (text.source.isNotEmpty) ...[
              SizedBox(height: context.gapMedium),
              Chip(
                label: Text(text.source),
                backgroundColor: isDark ? AppTheme.darkCard : AppTheme.cardBg,
                side: BorderSide(color: isDark ? AppTheme.borderLight : AppTheme.border),
              ),
            ],
            SizedBox(height: context.gapHuge),
            const Divider(color: AppTheme.border, height: 1),
            SizedBox(height: context.gapMedium),
            Row(
              children: [
                Icon(Icons.schedule, size: 18,
                    color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary),
                SizedBox(width: context.gapSmall),
                Text(
                  '预计阅读 $estMinutes 分钟 · 共 ${text.charCount} 字',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                  ),
                ),
              ],
            ),
            SizedBox(height: context.gapHuge),
            if (text.background.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16,
                      color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary),
                  SizedBox(width: context.gapSmall),
                  Text(
                    '背景介绍',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: context.gapSmall),
              Text(
                text.background,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: 1.6,
                ),
              ),
              SizedBox(height: context.gapXHuge),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.vermilion,
                  foregroundColor: AppTheme.cardBg,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                onPressed: () => _startReading(context, text),
                child: Text(
                  '开始阅读',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.cardBg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            SizedBox(height: context.gapXXHuge),
          ],
        ),
      ),
    );
  }

  void _startReading(BuildContext context, ChineseText text) async {
    final app = context.read<AppState>();
    if (app.hasUnrecordedReading && app.readingText?.id != text.id) {
      app.pauseReadingTimer();
      final discard = await showConfirmDialog(context,
        title: '确认切换',
        content: '当前文章阅读未满30秒，确定放弃？',
        confirmLabel: '放弃',
      );
      if (!discard) {
        app.resumeReadingTimer();
        return;
      }
      app.discardCurrentReading();
    }
    app.loadTextForReading(text.id);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}
