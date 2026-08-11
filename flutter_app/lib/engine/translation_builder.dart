/// 译文对照构建器 — 原文‖译文逐段交错拼接（方案 A）
///
/// 数据约定：articles 源文件里【原文】与【译文】均按空行分段，
/// 270 篇段数一致（剔噪口径）；译者名段（`（译者）`）原样保留，
/// 拼接时并入前一段。
class TranslationBuilder {
  TranslationBuilder._();

  static final RegExp _translatorNameRe = RegExp(r'^（[^）]{1,10}）$');

  /// 零宽字符，包裹译文段供 [AnnotatedTextBuilder] 区分样式
  static const String mark = '\u200B';

  static List<String> _splitParagraphs(String text) {
    return [for (final p in text.split('\n')) p.trim()] //
        .where((p) => p.isNotEmpty)
        .toList();
  }

  /// 译文段中独立成段的译者名（`（译者）`）并入紧邻的前一段；
  /// 段首无前段则独立成段（数据层实测不触发，防御保留）。
  static List<String> _mergeTranslatorNames(List<String> paras) {
    final merged = <String>[];
    for (final p in paras) {
      if (_translatorNameRe.hasMatch(p) && merged.isNotEmpty) {
        merged[merged.length - 1] =
            '${merged.last.trim()}${p.trim()}';
      } else {
        merged.add(p.trim());
      }
    }
    return merged;
  }

  /// 原文段数与译文段数强制对齐（防御）：
  /// 译文段数少 → 多余原文段配空译文段；译文段数多 → 多余段并入前段。
  static List<String> _align(int originalCount, List<String> translation) {
    if (translation.length == originalCount) return translation;
    if (translation.length < originalCount) {
      final result = List<String>.from(translation);
      while (result.length < originalCount) {
        result.add('');
      }
      return result;
    }
    final result = translation.sublist(0, originalCount - 1);
    result.add(translation.sublist(originalCount - 1).join());
    return result;
  }

  /// 构建交错段列表：`[原文1, 译文1, 原文2, 译文2, ...]`。
  /// 译文为空或无法分段时降级为纯原文段列表（不崩溃）。
  static List<String> buildInterleaved(String content, String translation) {
    final originalParas = _splitParagraphs(content);
    if (originalParas.isEmpty) return const [];
    if (translation.isEmpty) {
      return List<String>.from(originalParas);
    }

    final merged = _mergeTranslatorNames(_splitParagraphs(translation));
    final aligned = _align(originalParas.length, merged);

    final result = <String>[];
    for (var i = 0; i < aligned.length; i++) {
      result.add(originalParas[i]);
      final t = aligned[i];
      result.add(t.isEmpty ? '' : '$mark${t.trim()}$mark');
    }
    return result;
  }

  /// 段间 `\n` 连接成单文本，译文段保持零宽包裹。
  static String toInterleavedText(List<String> segments) {
    if (segments.isEmpty) return '';
    return segments.join('\n');
  }
}
