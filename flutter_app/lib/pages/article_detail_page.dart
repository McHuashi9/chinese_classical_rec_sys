import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/widgets/radar_chart.dart';
import 'package:chinese_classical_rec_sys/widgets/dialogs.dart';

const _deltaStar = 0.13;
const _sigma = 0.25;

double _learningGain(double dJ, double uJ) {
  final x = dJ - uJ - _deltaStar;
  return exp(-(x * x) / (2 * _sigma * _sigma));
}

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
              text.dynasty.isEmpty ? text.author : '${text.author} · ${text.dynasty}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            if (text.source.isNotEmpty) ...[
              SizedBox(height: context.gapMedium),
              Chip(
                label: Text(text.source),
                backgroundColor: isDark ? AppTheme.darkCard : AppTheme.cardBg,
                side: BorderSide(color: isDark ? AppTheme.borderLight : AppTheme.border),
              ),
            ],
            SizedBox(height: context.gapLg),
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
            SizedBox(height: context.gapLg),
            if (app.user != null && text.difficulties.length == abilityCount) ...[
              _buildDifficultyMatchSection(context, text, app.user!, isDark),
              SizedBox(height: context.gapLg),
              _buildEstimatedGainSection(context, text, app.user!, isDark),
              SizedBox(height: context.gapLg),
            ],
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
              SizedBox(height: context.gapXl),
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
            SizedBox(height: context.gapXxl),
          ],
        ),
      ),
    );
  }

  Widget _buildDifficultyMatchSection(
      BuildContext context, ChineseText text, User user, bool isDark) {
    final abilities = List.generate(abilityCount, (i) => user.getAbility(i).toDouble());
    final difficulties = text.difficulties;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.radar, size: 16,
                color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary),
            SizedBox(width: context.gapSmall),
            Text(
              '难度匹配',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
              ),
            ),
          ],
        ),
        SizedBox(height: context.gapMedium),
        Center(
          child: SizedBox(
            width: min(400, MediaQuery.sizeOf(context).width * 0.85),
            height: 250,
            child: RadarChart(
              targetValues: abilities,
              overlayValues: difficulties,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEstimatedGainSection(
      BuildContext context, ChineseText text, User user, bool isDark) {
    final gains = <double>[];
    for (int i = 0; i < abilityCount; i++) {
      gains.add(_learningGain(text.difficulties[i], user.getAbility(i)));
    }
    final total = gains.reduce((a, b) => a + b) / gains.length;
    final totalPct = (total * 100).toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.trending_up, size: 16,
                color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary),
            SizedBox(width: context.gapSmall),
            Text(
              '预计阅读收益',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
              ),
            ),
          ],
        ),
        SizedBox(height: context.gapSmall),
        Row(
          children: [
            Text(
              '综合收益 ',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
              ),
            ),
            Text(
              '$totalPct%',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFamily: AppTheme.fontUI,
                color: AppTheme.stoneGreen,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '  ·  $abilityCount 维平均',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
              ),
            ),
          ],
        ),
        SizedBox(height: context.gapMedium),
        ...List.generate(abilityCount, (i) => _buildGainBar(context, i, gains[i], isDark)),
      ],
    );
  }

  Widget _buildGainBar(BuildContext context, int idx, double gain, bool isDark) {
    final pct = (gain * 100).toStringAsFixed(0);

    return Padding(
      padding: EdgeInsets.only(bottom: context.cardPaddingV),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              abilityLabels[idx],
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: context.gapMedium),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Container(
                height: 10,
                color: AppTheme.stoneGreen.withAlpha(31),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: gain.clamp(0.0, 1.0),
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppTheme.stoneGreen,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: context.gapMedium),
          SizedBox(
            width: 48,
            child: Text(
              '$pct%',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
