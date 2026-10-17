import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';

import 'ffi_call.dart';

class TextRepository {
  final NativeBridge _bridge;
  final List<ChineseText> _textCache = [];

  TextRepository(this._bridge);

  void loadTextCache() {
    final count = _bridge.textGetCount();
    if (count < 0) requireBridgeCount(count, 'text_get_count');
    if (count == 0) {
      _textCache.clear();
      return;
    }

    final infos = calloc<TextInfo>(count);
    final copied = _bridge.textGetAll(infos, count);
    if (copied < 0) {
      calloc.free(infos);
      requireBridgeCount(copied, 'text_get_all');
    }
    final actual = copied > count ? count : copied;

    _textCache.clear();
    for (int i = 0; i < actual; i++) {
      final info = infos[i];
      _textCache.add(ChineseText.fromInfo(
        info.id,
        readCString(info.title, 256),
        readCString(info.author, 128),
        readCString(info.dynasty, 64),
        source: readCString(info.source, 64),
      ));
    }
    calloc.free(infos);
  }

  ChineseText? getTextDetail(int textId) {
    final detail = calloc<TextDetail>();
    final rc = _bridge.textGetDetail(textId, detail);
    if (rc != BridgeError.ok) {
      calloc.free(detail);
      if (rc == BridgeError.errText) return null;
      requireBridgeOk(rc, 'text_get_detail');
    }
    final d = detail.ref;
    final text = ChineseText.fromDetail(
      d.id,
      readCString(d.title, 256),
      readCString(d.author, 128),
      readCString(d.dynasty, 64),
      readCString(d.source, 64),
      readCString(d.background, 2048),
      readCString(d.content, 65536),
      d.charCount,
      [for (int i = 0; i < 10; i++) d.difficulties[i]],
    );
    calloc.free(detail);
    return text;
  }

  String getAnnotations(int textId) {
    final out = calloc<Uint8>(65536);
    final rc = _bridge.textGetAnnotations(textId, out.cast<Utf8>(), 65536);
    if (rc != BridgeError.ok) {
      calloc.free(out);
      if (rc == BridgeError.errText) return '';
      requireBridgeOk(rc, 'text_get_annotations');
    }
    final bytes = <int>[];
    for (int i = 0; i < 65536; i++) {
      final b = out[i];
      if (b == 0) break;
      bytes.add(b);
    }
    calloc.free(out);
    return utf8.decode(bytes, allowMalformed: true);
  }

  String getTranslation(int textId) {
    final out = calloc<Uint8>(65536);
    final rc = _bridge.textGetTranslation(textId, out.cast<Utf8>(), 65536);
    if (rc != BridgeError.ok) {
      calloc.free(out);
      if (rc == BridgeError.errText) return '';
      requireBridgeOk(rc, 'text_get_translation');
    }
    final bytes = <int>[];
    for (int i = 0; i < 65536; i++) {
      final b = out[i];
      if (b == 0) break;
      bytes.add(b);
    }
    calloc.free(out);
    return utf8.decode(bytes, allowMalformed: true);
  }

  int get textCount => _textCache.length;
  List<ChineseText> get texts => List.unmodifiable(_textCache);
}
