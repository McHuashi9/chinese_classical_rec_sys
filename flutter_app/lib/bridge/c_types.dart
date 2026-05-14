import 'dart:convert';
import 'dart:ffi';

/// C UserData struct — matches bridge/c_types.h
/// 10维能力向量 + 基础能力 + 最近阅读时间
@Packed(1)
final class UserData extends Struct {
  @Array(10)
  external Array<Double> abilities;

  @Array(10)
  external Array<Double> baseAbilities;

  @Int64()
  external int lastReadTime;
}

/// C TextInfo struct — 列表展示用摘要
@Packed(1)
final class TextInfo extends Struct {
  @Int32()
  external int id;

  @Array(256)
  external Array<Uint8> title;

  @Array(128)
  external Array<Uint8> author;

  @Array(64)
  external Array<Uint8> dynasty;

  @Array(64)
  external Array<Uint8> source;
}

/// C TextDetail struct — 含全文 + 难度向量
@Packed(1)
final class TextDetail extends Struct {
  @Int32()
  external int id;

  @Array(256)
  external Array<Uint8> title;

  @Array(128)
  external Array<Uint8> author;

  @Array(64)
  external Array<Uint8> dynasty;

  @Array(64)
  external Array<Uint8> source;

  @Array(2048)
  external Array<Uint8> background;

  @Array(65536)
  external Array<Uint8> content;

  @Int32()
  external int charCount;

  @Array(10)
  external Array<Double> difficulties;
}

/// C ReadingRecordData struct — 阅读历史记录
@Packed(1)
final class ReadingRecordData extends Struct {
  @Int32()
  external int id;

  @Int32()
  external int textId;

  @Double()
  external double readTime;

  @Int64()
  external int timestamp;
}

/// C 错误码
abstract class BridgeError {
  static const int ok = 0;
  static const int errGeneric = -1;
  static const int errNotInit = -2;
  static const int errUser = -3;
  static const int errText = -4;
}

/// 从 C 的 null-terminated Uint8 array 读取 Dart String
String readCString(Array<Uint8> arr, int maxLen) {
  final bytes = <int>[];
  for (int i = 0; i < maxLen; i++) {
    final b = arr[i];
    if (b == 0) break;
    bytes.add(b);
  }
  try {
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return String.fromCharCodes(bytes);
  }
}
