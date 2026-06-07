import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

class AnnotationParser {
  static Map<int, String> parse(String raw) {
    if (raw.isEmpty) return {};
    final re = RegExp(r'〔(\d+)〕(.+?)(?=〔|$)', dotAll: true);
    final matches = re.allMatches(raw);
    return {for (final m in matches) int.parse(m[1]!): m[2]!.trim()};
  }
}

class AnnotatedTextBuilder {
  static TextSpan build(
    String pageContent,
    Map<int, String> annotations,
    TextStyle baseStyle,
  ) {
    final markerStyle = baseStyle.copyWith(
      color: AppTheme.vermilion,
      fontSize: baseStyle.fontSize != null ? baseStyle.fontSize! * 0.75 : null,
      fontWeight: FontWeight.w600,
    );
    final spans = <InlineSpan>[];
    final re = RegExp(r'〔(\d+)〕');
    int lastEnd = 0;
    for (final match in re.allMatches(pageContent)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: pageContent.substring(lastEnd, match.start)));
      }
      final num = int.parse(match.group(1)!);
      spans.add(TextSpan(
        text: match.group(0),
        style: annotations.containsKey(num) ? markerStyle : baseStyle,
      ));
      lastEnd = match.end;
    }
    if (lastEnd < pageContent.length) {
      spans.add(TextSpan(text: pageContent.substring(lastEnd)));
      lastEnd = pageContent.length;
    }
    return TextSpan(style: baseStyle, children: spans);
  }

  static int? findAnnotationAtOffset(
    String pageContent,
    int offset,
    Map<int, String> annotations,
  ) {
    final re = RegExp(r'〔(\d+)〕');
    for (final match in re.allMatches(pageContent)) {
      if (offset >= match.start && offset < match.end) {
        final num = int.parse(match.group(1)!);
        if (annotations.containsKey(num)) return num;
      }
    }
    return null;
  }
}
