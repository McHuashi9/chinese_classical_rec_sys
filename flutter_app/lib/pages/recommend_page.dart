import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/recommend_card.dart';

class RecommendPage extends StatefulWidget {
  const RecommendPage({super.key});

  @override
  State<RecommendPage> createState() => _RecommendPageState();
}

class _RecommendPageState extends State<RecommendPage> {
  int _topK = 10;
  bool _initialLoad = true;
  double _lastAverageAbility = -1;
  AppState? _app;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _app!.addListener(_onAppChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
    });
  }

  @override
  void dispose() {
    _app?.removeListener(_onAppChanged);
    super.dispose();
  }

  void _onAppChanged() {
    if (!mounted) return;
    final avg = _app!.averageAbility;
    if (avg != _lastAverageAbility) {
      _lastAverageAbility = avg;
      _refresh();
    }
  }

  void _refresh() {
    _app?.getRecommendations(_topK);
    _initialLoad = false;
  }

  @override
  Widget build(BuildContext context) {
    final recs = context.select((AppState a) => a.recommendations);
    final isDark = context.select((AppState a) => a.darkMode);

    return Padding(
          padding: EdgeInsets.all(context.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // header
              LayoutBuilder(
                builder: (ctx, constraints) {
                  if (constraints.maxWidth < 480) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '为你推荐',
                          style: Theme.of(context).textTheme.headlineLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: context.gapMedium),
                        _buildSpinBox(isDark),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Text(
                        '为你推荐',
                        style: Theme.of(context).textTheme.headlineLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      _buildSpinBox(isDark),
                    ],
                  );
                },
              ),
              SizedBox(height: context.gapHuge),
              const Divider(color: AppTheme.border, height: 1),
              SizedBox(height: context.gapHuge),

              // content
              Expanded(
                child: recs.isEmpty && !_initialLoad
                    ? Center(
                        child: Text(
                          '能力变化时将自动生成推荐',
                          style: TextStyle(
                            fontSize: 16,
                            fontFamily: AppTheme.fontUI,
                            color: isDark
                                ? AppTheme.darkInkSecondary
                                : AppTheme.inkSecondary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: recs.length,
                        itemBuilder: (ctx, i) => RecommendCard(result: recs[i]),
                      ),
              ),
            ],
          ),
    );
  }

  Widget _buildSpinBox(bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('篇数', style: TextStyle(
          fontSize: 14,
          fontFamily: AppTheme.fontUI,
          color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
        )),
        SizedBox(width: context.gapMedium),
        IconButton(
          icon: const Icon(Icons.remove, size: 18),
          visualDensity: VisualDensity.compact,
          onPressed: _topK > 1
              ? () {
                  _topK--;
                  _refresh();
                }
              : null,
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$_topK',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontFamily: AppTheme.fontUI,
              color: isDark ? AppTheme.darkInk : AppTheme.ink,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add, size: 18),
          visualDensity: VisualDensity.compact,
          onPressed: _topK < 50
              ? () {
                  _topK++;
                  _refresh();
                }
              : null,
        ),
      ],
    );
  }
}
