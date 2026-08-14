import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/recommendation.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';

/// filterRecommendations：推荐列表剔除已读篇目（L2-1）。
/// 纯 Dart 函数，无需 FFI；RecommendationEngine 本身由集成测试覆盖。
void main() {
  ChineseText text(int id) =>
      ChineseText(id: id, title: '篇$id', author: 'a', dynasty: 'd');

  List<RecommendResult> ranked(List<int> ids) => [
        for (final id in ids) RecommendResult(text: text(id), probability: 1.0 / (id + 1)),
      ];

  test('已读篇目被剔除，其余保序截断到 topK', () {
    final all = ranked([1, 2, 3, 4, 5]);
    final out = filterRecommendations(all, {2, 4}, 3);
    expect(out.map((r) => r.text.id).toList(), [1, 3, 5]);
  });

  test('剔除后不足 topK 时返回全部剩余', () {
    final all = ranked([1, 2, 3]);
    final out = filterRecommendations(all, {1, 2}, 5);
    expect(out.map((r) => r.text.id).toList(), [3]);
  });

  test('空排除集等价于截断', () {
    final all = ranked([1, 2, 3, 4]);
    expect(filterRecommendations(all, {}, 2).map((r) => r.text.id).toList(), [1, 2]);
  });

  test('全部已读返回空', () {
    expect(filterRecommendations(ranked([1, 2]), {1, 2}, 2), isEmpty);
  });
}
