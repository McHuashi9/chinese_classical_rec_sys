import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/radar_chart.dart';
import 'package:chinese_classical_rec_sys/widgets/stats_card.dart';
import 'package:chinese_classical_rec_sys/widgets/recent_reading_list.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';

class MyPage extends StatelessWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.select((AppState a) => a.user);

    return user != null
        ? _MyContent(user: user)
        : const Center(child: CircularProgressIndicator());
  }
}

class _MyContent extends StatelessWidget {
  final User user;

  const _MyContent({required this.user});

  double get _average {
    double sum = 0;
    for (int i = 0; i < 10; i++) {
      sum += user.getAbility(i);
    }
    return sum / 10;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.read<AppState>().darkMode;
    final app = context.read<AppState>();

    return SingleChildScrollView(
      padding: EdgeInsets.all(context.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header
          _buildHeader(context, isDark),
          SizedBox(height: context.gapHuge),
          const Divider(color: AppTheme.border, height: 1),
          SizedBox(height: context.gapXHuge),

          // radar
          _buildRadar(context),
          SizedBox(height: context.gapXXHuge),

          // 2x2 stats
          _buildStats(context, app),

          // dimension bars
          ...List.generate(10, (i) => _buildDimBar(context, i, isDark)),
          SizedBox(height: context.gapXXHuge),

          // recent reading list
          _buildRecentList(context, app),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        if (constraints.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '我的',
                style: Theme.of(context).textTheme.headlineLarge,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: context.gapSmall),
              Text('综合: ${(_average * 100).toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                  )),
            ],
          );
        }
        return Row(
          children: [
            Text(
              '我的',
              style: Theme.of(context).textTheme.headlineLarge,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            Text('综合: ${(_average * 100).toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                )),
          ],
        );
      },
    );
  }

  Widget _buildRadar(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final sz = constraints.maxWidth.clamp(0.0, 400.0);
        return Center(
          child: SizedBox(
            width: sz,
            height: sz,
            child: RadarChart(targetValues: List.generate(10, (i) => user.getAbility(i).toDouble())),
          ),
        );
      },
    );
  }

  Widget _buildStats(BuildContext context, AppState app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('阅读统计', style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: context.gapMedium),
        StatsCard(stats: app.getReadingStats()),
        SizedBox(height: context.gapXXHuge),
      ],
    );
  }

  Widget _buildRecentList(BuildContext context, AppState app) {
    final records = app.getRecentHistory();
    if (records.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('最近阅读', style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: context.gapMedium),
        RecentReadingList(
          records: records.take(10).toList(),
          onTap: (textId) {
            final ok = app.loadTextForReading(textId);
            if (ok && context.mounted) {
              app.switchPage(0);
            }
          },
        ),
      ],
    );
  }

  Widget _buildDimBar(BuildContext context, int idx, bool isDark) {
    final val = user.getAbility(idx).toDouble().clamp(0.0, 1.0);
    final pct = (val * 100).toStringAsFixed(0);

    return Padding(
      padding: EdgeInsets.only(bottom: context.cardPaddingV),
      child: Row(
        children: [
          SizedBox(
            width: 76,
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
                color: AppTheme.vermilion.withAlpha(31),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: val,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppTheme.vermilion,
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
}
