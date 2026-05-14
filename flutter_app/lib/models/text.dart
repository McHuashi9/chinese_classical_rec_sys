/// Dart Text 模型 — 古文元数据 + 10维难度
class ChineseText {
  final int id;
  final String title;
  final String author;
  final String dynasty;
  final String source;
  final String background;
  final String content;
  final int charCount;
  final List<double> difficulties;

  const ChineseText({
    required this.id,
    required this.title,
    required this.author,
    required this.dynasty,
    this.source = '',
    this.background = '',
    this.content = '',
    this.charCount = 0,
    this.difficulties = const [],
  });

  /// 从 C [TextInfo] 创建摘要视图 (不含全文内容)
  factory ChineseText.fromInfo(int id, String title, String author, String dynasty, {String source = ''}) {
    return ChineseText(
      id: id,
      title: title,
      author: author,
      dynasty: dynasty,
      source: source,
    );
  }

  /// 从 C [TextDetail] 创建完整视图
  factory ChineseText.fromDetail(
    int id,
    String title,
    String author,
    String dynasty,
    String source,
    String background,
    String content,
    int charCount,
    List<double> difficulties,
  ) {
    return ChineseText(
      id: id,
      title: title,
      author: author,
      dynasty: dynasty,
      source: source,
      background: background,
      content: content,
      charCount: charCount,
      difficulties: difficulties,
    );
  }

  double get averageDifficulty {
    if (difficulties.isEmpty) return 0;
    return difficulties.reduce((a, b) => a + b) / difficulties.length;
  }
}

/// 推荐结果项
class RecommendResult {
  final ChineseText text;
  final double probability;

  const RecommendResult({required this.text, required this.probability});
}
