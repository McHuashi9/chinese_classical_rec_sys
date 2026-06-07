import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

class ParsedEntry {
  final String headword;
  final String content;

  const ParsedEntry({required this.headword, required this.content});
}

class AnnotationParser {
  static Map<int, String> parse(String raw) {
    if (raw.isEmpty) return {};
    final re = RegExp(r'〔(\d+)〕(.+?)(?=〔|$)', dotAll: true);
    final matches = re.allMatches(raw);
    return {for (final m in matches) int.parse(m[1]!): m[2]!.trim()};
  }

  static ParsedEntry parseEntry(String entry) {
    final textbookRe = RegExp(r'^\[(.+?)\](.*)');
    final textbookMatch = textbookRe.firstMatch(entry);
    if (textbookMatch != null) {
      final word = textbookMatch.group(1)!.trim();
      if (word.isNotEmpty) {
        return ParsedEntry(
          headword: word,
          content: textbookMatch.group(2)!.trim(),
        );
      }
    }

    final anthologyRe = RegExp(r'^(.+?)：(.+)');
    final anthologyMatch = anthologyRe.firstMatch(entry);
    if (anthologyMatch != null) {
      final word = anthologyMatch.group(1)!.trim();
      if (word.isNotEmpty) {
        return ParsedEntry(
          headword: word,
          content: anthologyMatch.group(2)!.trim(),
        );
      }
    }

    return ParsedEntry(headword: '', content: entry);
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

  static TextSelection markerSelection(String pageContent, int number) {
    final re = RegExp(r'〔(\d+)〕');
    for (final match in re.allMatches(pageContent)) {
      if (int.parse(match.group(1)!) == number) {
        return TextSelection(
          baseOffset: match.start,
          extentOffset: match.end,
        );
      }
    }
    return const TextSelection.collapsed(offset: 0);
  }
}
