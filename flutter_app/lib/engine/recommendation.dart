import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';

/// 从推荐结果中剔除 [excludeTextIds]（如已读篇目）后截断到 [topK]。
/// 输入须按概率降序；返回仍保序（推荐位不被已读篇目占用）。
/// 独立函数便于单测（RecommendationEngine 依赖 FFI 无法在单测中构造）。
List<RecommendResult> filterRecommendations(
    List<RecommendResult> all, Set<int> excludeTextIds, int topK) {
  final filtered = <RecommendResult>[];
  for (final r in all) {
    if (excludeTextIds.contains(r.text.id)) continue;
    filtered.add(r);
    if (filtered.length >= topK) break;
  }
  return filtered;
}

class RecommendationEngine {
  final NativeBridge _bridge;

  RecommendationEngine(this._bridge);

  List<RecommendResult> getRecommendations(User user, int topK, List<ChineseText> textCache) {
    if (textCache.isEmpty) return [];

    final validTopK = topK.clamp(1, textCache.length);
    final outIds = calloc<Int32>(validTopK);
    final outProbs = calloc<Double>(validTopK);

    final rc = _bridge.recommend(user.ptr, validTopK, outIds, outProbs, validTopK, validTopK);
    if (rc != BridgeError.ok) {
      calloc.free(outIds);
      calloc.free(outProbs);
      return [];
    }

    final results = <RecommendResult>[];
    for (int i = 0; i < validTopK; i++) {
      final textId = outIds[i];
      final prob = outProbs[i];
      final text = textCache.cast<ChineseText?>().firstWhere(
        (t) => t?.id == textId,
        orElse: () => null,
      );
      if (text == null) continue;
      results.add(RecommendResult(text: text, probability: prob));
    }

    calloc.free(outIds);
    calloc.free(outProbs);
    return results;
  }
}
