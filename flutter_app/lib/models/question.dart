import 'dart:convert';
import 'dart:ffi';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';

/// Dart 视图层题目模型 — 封装 [QuestionData] C struct
class Question {
  final Pointer<QuestionData> ptr;

  /// 题组整块内存（getQuestionsForText 批量分配），由调用方统一释放
  final Pointer<QuestionData> owner;

  Question(this.ptr, {required this.owner});

  static const optionSize = 512;

  int get id => ptr.ref.id;

  int get textId => ptr.ref.textId;

  String get qType => readCString(ptr.ref.qType, 16);

  String get stem => readCString(ptr.ref.stem, 1024);

  String option(int index) {
    final base = ptr.ref.options;
    final bytes = <int>[];
    for (int i = 0; i < optionSize; i++) {
      final b = base[index * optionSize + i];
      if (b == 0) break;
      bytes.add(b);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String get dims => readCString(ptr.ref.dims, 64);

  String get explanation => readCString(ptr.ref.explanation, 2048);

  double get difficulty => ptr.ref.difficulty;

  /// 划线词所在原句（空串表示无）
  String get context => readCString(ptr.ref.context, 1024);

  /// 划线区间（context 内下标；无 context 时为 -1/0）
  int get markStart => ptr.ref.markStart;

  int get markLen => ptr.ref.markLen;

  /// 解析 dims CSV（如 "3,4,9" → [3, 4, 9]）
  List<int> get dimensionList {
    final parts = dims.split(',');
    return [
      for (final p in parts)
        if (p.trim().isNotEmpty) int.tryParse(p.trim()) ?? -1,
    ];
  }
}