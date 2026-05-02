import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
import 'package:chinese_classical_rec_sys/widgets/recommend_card.dart';

/// 推荐页面 — 等价于 QML RecommendPage
class RecommendPage extends StatefulWidget {
  const RecommendPage({super.key});

  @override
  State<RecommendPage> createState() => _RecommendPageState();
}

class _RecommendPageState extends State<RecommendPage> {
  int _topK = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().getRecommendations(_topK);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final recs = app.recommendations;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text('推荐数量:'),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onSubmitted: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n > 0) {
                      setState(() => _topK = n);
                      app.getRecommendations(n);
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: () => app.getRecommendations(_topK),
                child: const Text('刷新推荐'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: recs.length,
            itemBuilder: (ctx, i) => RecommendCard(result: recs[i]),
          ),
        ),
      ],
    );
  }
}
