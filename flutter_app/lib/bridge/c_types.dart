import 'dart:ffi';

/// C UserData struct — matches bridge/c_types.h
/// 10维能力向量 + 基础能力 + 姓名 + 最近阅读时间
final class UserData extends Struct {
  @Array(128)
  external Array<Uint8> name;

  @Array(10)
  external Array<Double> abilities;

  @Array(10)
  external Array<Double> baseAbilities;

  @Int64()
  external int lastReadTime;

  static UserData allocate(Allocator allocator) =>
      allocator<UserData>();
}

/// C TextInfo struct — 列表展示用摘要
final class TextInfo extends Struct {
  @Int32()
  external int id;

  @Array(256)
  external Array<Uint8> title;

  @Array(128)
  external Array<Uint8> author;

  @Array(64)
  external Array<Uint8> dynasty;

  static TextInfo allocate(Allocator allocator) =>
      allocator<TextInfo>();
}

/// C TextDetail struct — 含全文 + 难度向量
final class TextDetail extends Struct {
  @Int32()
  external int id;

  @Array(256)
  external Array<Uint8> title;

  @Array(128)
  external Array<Uint8> author;

  @Array(64)
  external Array<Uint8> dynasty;

  @Array(65536)
  external Array<Uint8> content;

  @Array(10)
  external Array<Double> difficulties;

  static TextDetail allocate(Allocator allocator) =>
      allocator<TextDetail>();
}

/// C 错误码
abstract class BridgeError {
  static const int ok = 0;
  static const int errGeneric = -1;
  static const int errNotInit = -2;
  static const int errUser = -3;
  static const int errText = -4;
}
