import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';

/// 阅读页面 — 等价于 QML ReadPage
/// 乌丝栏背景用 RepeatingLinearGradient 替代 Canvas 节点
class ReadPage extends StatelessWidget {
  const ReadPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final text = app.readingText;

    if (text == null) {
      return const Center(child: Text('请从文库选择一篇古文'));
    }

    return Column(
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text.title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text('${text.author} · ${text.dynasty}',
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        // 正文区域
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              // TODO: 乌丝栏背景 (RepeatingLinearGradient)
              color: Color(0xFFF5F0E8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            child: GestureDetector(
              onTapDown: (details) {
                final box = context.findRenderObject() as RenderBox;
                final dy = details.localPosition.dy;
                final midY = box.size.height / 2;
                if (dy < midY) {
                  // TODO: prevPage
                } else {
                  // TODO: nextPage
                }
              },
              child: Text(
                text.content,
                style: const TextStyle(
                  fontSize: 18,
                  fontFamily: 'SourceHanSerifSC',
                  height: 2.0,
                ),
              ),
            ),
          ),
        ),
        // 页脚导航
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('第 ${app.readingPage + 1} 页'),
        ),
      ],
    );
  }
}
