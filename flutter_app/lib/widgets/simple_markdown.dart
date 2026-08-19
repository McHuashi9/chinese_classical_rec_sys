import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 极简 Markdown 渲染器：支持公告场景需要的标题、段落、无序列表，
/// 以及行内 `**加粗**` 与 `` `代码` ``。
///
/// 不引入第三方 Markdown 依赖；如果未来公告需要链接/表格等富文本，再评估
/// 接入完整渲染器。
class SimpleMarkdown extends StatelessWidget {
  final String data;

  const SimpleMarkdown({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks) _buildBlock(context, block),
      ],
    );
  }

  Widget _buildBlock(BuildContext context, _Block block) {
    final theme = Theme.of(context);
    final Widget child;
    switch (block) {
      case _HeadingBlock(:final level, :final text):
        child = switch (level) {
          1 => Text.rich(
              TextSpan(
                style: theme.textTheme.titleLarge,
                children: _inlineSpans(context, text),
              ),
            ),
          2 => Text.rich(
              TextSpan(
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: context.accent),
                children: _inlineSpans(context, text),
              ),
            ),
          _ => Text.rich(
              TextSpan(
                style: theme.textTheme.titleSmall,
                children: _inlineSpans(context, text),
              ),
            ),
        };
      case _ParagraphBlock(:final text):
        child = Text.rich(
          TextSpan(
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            children: _inlineSpans(context, text),
          ),
        );
      case _ListBlock(:final items):
        child = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('· '),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(height: 1.5),
                          children: _inlineSpans(context, item),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: child,
    );
  }

  /// 解析行内 `**加粗**` 与 `` `代码` ``，其余按普通文本输出。
  List<InlineSpan> _inlineSpans(BuildContext context, String text) {
    final pattern = RegExp(r'(\*\*.+?\*\*|`[^`]+`)');
    final spans = <InlineSpan>[];
    var start = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      final token = match.group(0)!;
      if (token.startsWith('**')) {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ));
      } else {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: const TextStyle(fontFamily: 'monospace'),
        ));
      }
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return spans;
  }
}

sealed class _Block {}

class _HeadingBlock extends _Block {
  final int level;
  final String text;

  _HeadingBlock({required this.level, required this.text});
}

class _ParagraphBlock extends _Block {
  final String text;

  _ParagraphBlock(this.text);
}

class _ListBlock extends _Block {
  final List<String> items;

  _ListBlock(this.items);
}

List<_Block> _parseBlocks(String data) {
  final lines = data.split('\n');
  final blocks = <_Block>[];
  var i = 0;

  while (i < lines.length) {
    final trimmed = lines[i].trim();
    if (trimmed.isEmpty) {
      i++;
      continue;
    }

    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
    if (heading != null) {
      blocks.add(_HeadingBlock(
        level: heading.group(1)!.length,
        text: heading.group(2)!,
      ));
      i++;
      continue;
    }

    if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      final items = <String>[];
      while (i < lines.length) {
        final current = lines[i].trim();
        if (current.startsWith('- ')) {
          items.add(current.substring(2).trim());
          i++;
        } else if (current.startsWith('* ')) {
          items.add(current.substring(2).trim());
          i++;
        } else {
          break;
        }
      }
      blocks.add(_ListBlock(items));
      continue;
    }

    final paragraphLines = <String>[];
    while (i < lines.length) {
      final current = lines[i].trim();
      if (current.isEmpty) break;
      if (current.startsWith('#') ||
          current.startsWith('- ') ||
          current.startsWith('* ')) {
        break;
      }
      paragraphLines.add(current);
      i++;
    }
    blocks.add(_ParagraphBlock(paragraphLines.join('\n')));
  }

  return blocks;
}
