import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/radar_chart.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';

const _dimLabels = [
  '平均句长',
  '句子数量',
  '虚词比例',
  '字频对数',
  '通假密度',
  '古PPL',
  '现PPL',
  'MATTR',
  '典故密度',
  '语义复杂度',
];

class AbilityPage extends StatelessWidget {
  const AbilityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.select((AppState a) => a.user);

    return user != null
        ? _AbilityContent(abilities: _getAbilities(user))
        : const Center(child: CircularProgressIndicator());
  }

  List<double> _getAbilities(User user) {
    return List.generate(10, (i) => user.getAbility(i).toDouble());
  }
}

class _AbilityContent extends StatelessWidget {
  final List<double> abilities;

  const _AbilityContent({required this.abilities});

  double get _average =>
      abilities.isEmpty ? 0 : abilities.reduce((a, b) => a + b) / abilities.length;

  @override
  Widget build(BuildContext context) {
    final isDark = context.read<AppState>().darkMode;
    final isSmall = MediaQuery.sizeOf(context).width < 600;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // header
          Row(
            children: [
              Flexible(
                child: Text(
                  '我的能力',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontSize: isSmall ? 24 : 36,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              Text(
                '综合: ${(_average * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 20,
                  fontFamily: AppTheme.fontUI,
                  color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 24),

          // radar chart
          LayoutBuilder(
            builder: (ctx, constraints) {
              final sz = constraints.maxWidth.clamp(0.0, 400.0);
              return Center(
                child: SizedBox(
                  width: sz,
                  height: sz,
                  child: RadarChart(targetValues: abilities),
                ),
              );
            },
          ),
          const SizedBox(height: 32),

          // dimension bars
          ...List.generate(10, (i) => _buildDimBar(i, isDark)),
        ],
      ),
    );
  }

  Widget _buildDimBar(int idx, bool isDark) {
    final val = abilities[idx].clamp(0.0, 1.0);
    final pct = (val * 100).toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              _dimLabels[idx],
              style: TextStyle(
                fontSize: 14,
                fontFamily: AppTheme.fontUI,
                color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
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
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              '$pct%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontFamily: AppTheme.fontUI,
                color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
