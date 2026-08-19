import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';

/// C ABI 布局断言：与 bridge/c_types.h 的 7 个 static_assert 一一对应。
/// 任何一侧字段增删/顺序调换都会在这里（或 C++ 编译期）立即失败，
/// 而不是等 FFI 集成测试跑起来才发现静默错位。
void main() {
  test('C ABI 结构尺寸与 bridge/c_types.h 一致（@Packed(1) 布局）', () {
    expect(sizeOf<UserData>(), 216);
    expect(sizeOf<ProfileData>(), 88);
    expect(sizeOf<TextInfo>(), 516);
    expect(sizeOf<TextDetail>(), 68184);
    expect(sizeOf<ReadingRecordData>(), 24);
    expect(sizeOf<QuestionData>(), 6248);
    expect(sizeOf<ReviewItemData>(), 24);
  });
}
