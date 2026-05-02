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
    final app = context.watch<AppState>();
    final recs = app.recommendations;
    final isDark = app.darkMode;

    return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // header
              Row(
                children: [
                  Text('为你推荐', style: Theme.of(context).textTheme.headlineLarge),
                  const Spacer(),
                  _buildSpinBox(isDark),
                  const SizedBox(width: 12),
                  _buildGenerateButton(isDark),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: AppTheme.border, height: 1),
              const SizedBox(height: 16),

              // content
              Expanded(
                child: recs.isEmpty && !_initialLoad
                    ? Center(
                        child: Text(
                          '点击「生成推荐」获取个性化篇目',
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
                        itemBuilder: (ctx, i) => _AnimatedListItem(
                          index: i,
                          child: RecommendCard(result: recs[i]),
                        ),
                      ),
              ),
            ],
          ),
    );
  }

  Widget _buildSpinBox(bool isDark) {
    return Row(
      children: [
        Text('篇数', style: TextStyle(
          fontSize: 14,
          fontFamily: AppTheme.fontUI,
          color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
        )),
        const SizedBox(width: 8),
        _SpinButton(
          icon: Icons.remove,
          onTap: _topK > 1
              ? () => setState(() {
                    _topK--;
                    _refresh();
                  })
              : null,
        ),
        Container(
          width: 44,
          height: 32,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppTheme.border, width: 1),
            ),
          ),
          child: Text(
            '$_topK',
            style: TextStyle(
              fontSize: 16,
              fontFamily: AppTheme.fontUI,
              color: isDark ? AppTheme.darkInk : AppTheme.ink,
            ),
          ),
        ),
        _SpinButton(
          icon: Icons.add,
          onTap: _topK < 50
              ? () => setState(() {
                    _topK++;
                    _refresh();
                  })
              : null,
        ),
      ],
    );
  }

  Widget _buildGenerateButton(bool isDark) {
    return GestureDetector(
      onTap: _refresh,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          color: AppTheme.vermilion,
          child: const Text(
            '生成推荐',
            style: TextStyle(
              fontSize: 14,
              fontFamily: AppTheme.fontUI,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpinButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _SpinButton({required this.icon, this.onTap});

  @override
  State<_SpinButton> createState() => _SpinButtonState();
}

class _SpinButtonState extends State<_SpinButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      onTap: enabled ? widget.onTap : null,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.3,
          child: Container(
            width: 28,
            height: 32,
            decoration: BoxDecoration(
              color: _hovered && enabled
                  ? AppTheme.borderLight
                  : Colors.transparent,
              border: Border.all(color: AppTheme.border, width: 1),
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 14, color: AppTheme.ink),
          ),
        ),
      ),
    );
  }
}

class _AnimatedListItem extends StatefulWidget {
  final int index;
  final Widget child;

  const _AnimatedListItem({required this.index, required this.child});

  @override
  State<_AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<_AnimatedListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: Duration(milliseconds: 200 + widget.index * 30),
      vsync: this,
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: widget.child,
    );
  }
}
