import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';

/// Dart 视图层 User 类 — 封装 [UserData] C struct 的读写
class User {
  final Pointer<UserData> ptr;
  final bool _ownsMemory;

  User(this.ptr, {bool owns = false}) : _ownsMemory = owns;

  factory User.allocate(Allocator allocator) =>
      User(allocator<UserData>(), owns: true);

  String get name => readCString(ptr.ref.name, 128);
  set name(String value) {
    final src = value.toNativeUtf8(allocator: malloc);
    final u8 = src.cast<Uint8>();
    final len = value.length < 127 ? value.length : 127;
    for (var i = 0; i < len; i++) {
      ptr.ref.name[i] = (u8 + i).value;
    }
    ptr.ref.name[len] = 0;
    malloc.free(src);
  }

  double getAbility(int index) => ptr.ref.abilities[index];
  void setAbility(int index, double value) {
    ptr.ref.abilities[index] = value;
  }

  double getBaseAbility(int index) => ptr.ref.baseAbilities[index];
  void setBaseAbility(int index, double value) {
    ptr.ref.baseAbilities[index] = value;
  }

  int get lastReadTime => ptr.ref.lastReadTime;
  set lastReadTime(int value) => ptr.ref.lastReadTime = value;

  double get averageAbility {
    double sum = 0;
    for (int i = 0; i < 10; i++) {
      sum += getAbility(i);
    }
    return sum / 10.0;
  }

  Map<String, double> get breakdown {
    const names = [
      '平均句长', '句子数', '虚词比例', '字均对数频次', '通假字密度',
      '古汉语困惑度', '今汉语困惑度', '词汇多样性', '典故密度', '语义复杂度',
    ];
    final map = <String, double>{};
    for (int i = 0; i < 10; i++) {
      map[names[i]] = getAbility(i);
    }
    return map;
  }

  void dispose() {
    if (_ownsMemory) malloc.free(ptr);
  }
}
