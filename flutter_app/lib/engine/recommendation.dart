import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';

/// 推荐引擎 FFI 封装 + 本地文本缓存
class RecommendationEngine {
  final NativeBridge _bridge;
  final List<ChineseText> _textCache = [];

  RecommendationEngine(this._bridge);

  /// 从 C 层加载全部文本摘要到本地缓存
  void loadTextCache() {
    final count = _bridge.textGetCount();
    if (count <= 0) return;

    final infos = calloc<TextInfo>(count);
    _bridge.textGetAll(infos, count);

    _textCache.clear();
    for (int i = 0; i < count; i++) {
      final info = infos[i];
      _textCache.add(ChineseText.fromInfo(
        info.id,
        readCString(info.title, 256),
        readCString(info.author, 128),
        readCString(info.dynasty, 64),
      ));
    }
    calloc.free(infos);
  }

  /// 获取文本全文详情
  ChineseText? getTextDetail(int textId) {
    final detail = calloc<TextDetail>();
    final rc = _bridge.textGetDetail(textId, detail);
    if (rc != BridgeError.ok) {
      calloc.free(detail);
      return null;
    }
    final d = detail.ref;
    final text = ChineseText.fromDetail(
      d.id,
      readCString(d.title, 256),
      readCString(d.author, 128),
      readCString(d.dynasty, 64),
      readCString(d.content, 65536),
      [for (int i = 0; i < 10; i++) d.difficulties[i]],
    );
    calloc.free(detail);
    return text;
  }

  /// 获取推荐列表 (topK 篇)
  List<RecommendResult> getRecommendations(User user, int topK) {
    if (_textCache.isEmpty) return [];

    final validTopK = topK.clamp(1, _textCache.length);
    final outIds = calloc<Int32>(validTopK);
    final outProbs = calloc<Double>(validTopK);

    _bridge.recommend(user.ptr, validTopK, outIds, outProbs);

    final results = <RecommendResult>[];
    for (int i = 0; i < validTopK; i++) {
      final textId = outIds[i];
      final prob = outProbs[i];
      final text = _textCache.firstWhere((t) => t.id == textId);
      results.add(RecommendResult(text: text, probability: prob));
    }

    calloc.free(outIds);
    calloc.free(outProbs);
    return results;
  }

  int get textCount => _textCache.length;
  List<ChineseText> get texts => List.unmodifiable(_textCache);
}
