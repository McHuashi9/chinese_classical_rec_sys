import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/pages/review_list_page.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/radar_chart.dart';
import 'package:chinese_classical_rec_sys/widgets/stats_card.dart';
import 'package:chinese_classical_rec_sys/widgets/recent_reading_list.dart';
import 'package:chinese_classical_rec_sys/widgets/empty_state.dart';
import 'package:chinese_classical_rec_sys/widgets/profile_avatar.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';

class MyPage extends StatelessWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.select((UserController u) => u.user);
    final reviewCount = context.select((UserController u) => u.reviewCount);
    final totalReviewCount =
        context.select((UserController u) => u.totalReviewCount);
    final profileName =
        context.select((UserController u) => u.activeProfileName);
    final activeUserId = context.select((UserController u) => u.activeUserId);

    return user != null
        ? _MyContent(
            user: user,
            reviewCount: reviewCount,
            totalReviewCount: totalReviewCount,
            profileName: profileName,
            activeUserId: activeUserId,
          )
        : const Center(child: CircularProgressIndicator());
  }
}

class _MyContent extends StatelessWidget {
  final User user;
  final int reviewCount;
  final int totalReviewCount;
  final String? profileName;
  final int? activeUserId;

  const _MyContent({
    required this.user,
    required this.reviewCount,
    required this.totalReviewCount,
    required this.profileName,
    required this.activeUserId,
  });

  double get _average {
    double sum = 0;
    for (int i = 0; i < 10; i++) {
      sum += user.getAbility(i);
    }
    return sum / 10;
  }

  @override
  Widget build(BuildContext context) {
    final coord = context.read<AppCoordinator>();

    if (_average <= 0.001 && coord.getTotalReadCount() == 0) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(context.pagePadding),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EmptyState(
              title: '去读一篇文章开始吧',
              subtitle: '阅读达到本文最低阅读时间后，这里会展示你的能力画像与阅读统计',
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(context.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header
          _buildHeader(context),
          SizedBox(height: context.gapLg),
          Divider(color: context.appColors.border, height: 1),
          SizedBox(height: context.gapXl),

          // radar
          _buildRadar(context),
          SizedBox(height: context.gapXxl),

          // 2x2 stats
          _buildStats(context, coord),

          // 错题复习入口：有错题总数即显示（含未到期），到期数并列展示。
          if (totalReviewCount > 0) ...[
            SizedBox(height: context.gapLg),
            _buildReviewCard(context, reviewCount, totalReviewCount),
          ],

          // dimension bars
          ...List.generate(10, (i) => _buildDimBar(context, i)),
          SizedBox(height: context.gapXxl),

          // recent reading list
          _buildRecentList(context, coord),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
                        color: context.appColors.inkSecondary,
                      )),
              if (profileName != null) ...[
                SizedBox(height: context.gapSmall),
                Row(
                  children: [
                    ProfileAvatar(
                        name: profileName!, id: activeUserId ?? 0, radius: 10),
                    SizedBox(width: context.gapSmall),
                    Flexible(
                      child: Text('当前用户 · $profileName',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: context.accent,
                                  )),
                    ),
                  ],
                ),
              ],
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
            if (profileName != null) ...[
              SizedBox(width: context.gapMedium),
              ProfileAvatar(
                  name: profileName!, id: activeUserId ?? 0, radius: 12),
              SizedBox(width: context.gapSmall),
              Expanded(
                child: Text('当前用户 · $profileName',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: context.accent,
                        ),
                    overflow: TextOverflow.ellipsis),
              ),
            ] else
              const Spacer(),
            Text('综合: ${(_average * 100).toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: context.appColors.inkSecondary,
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
            child: RadarChart(
                targetValues:
                    List.generate(10, (i) => user.getAbility(i).toDouble())),
          ),
        );
      },
    );
  }

  Widget _buildStats(BuildContext context, AppCoordinator coord) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('阅读统计', style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: context.gapMedium),
        StatsCard(stats: coord.getReadingStats()),
        SizedBox(height: context.gapXxl),
      ],
    );
  }

  Widget _buildReviewCard(BuildContext context, int count, int total) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.gapXxl),
      child: Material(
        color: context.appColors.cardBg,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ReviewListPage()),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: context.accent),
            ),
            child: Row(
              children: [
                Icon(Icons.assignment_late, size: 20, color: context.accent),
                SizedBox(width: context.gapMedium),
                Expanded(
                  child: Text(
                    '错题复习 · 共 $total 题 · $count 道到期',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: context.accent,
                        ),
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 20, color: context.appColors.inkSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentList(BuildContext context, AppCoordinator coord) {
    final records = coord.getRecentHistory();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('最近阅读', style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: context.gapMedium),
        RecentReadingList(
          records: records.take(10).toList(),
          onTap: (textId) {
            final ok = coord.loadTextForReading(textId);
            if (ok && context.mounted) {
              coord.navCtrl.switchPage(0);
            }
          },
        ),
      ],
    );
  }

  Widget _buildDimBar(BuildContext context, int idx) {
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
                    color: context.appColors.inkSecondary,
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
                color: context.accent.withAlpha(31),
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: val),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  builder: (ctx, v, child) => FractionallySizedBox(
                    widthFactor: v,
                    child: child,
                  ),
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: context.accent,
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
                    color: context.appColors.inkSecondary,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
