import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';

const abilityLabels = [
  '平均句长',
  '句子数量',
  '虚词比例',
  '字频对数',
  '通假密度',
  '古PPL',
  '现PPL',
  'MATTR',
  '典故密度',
  '语义复杂度',
];
const abilityCount = 10;

/// Dart 视图层 User 类 — 封装 [UserData] C struct 的读写
class User {
  final Pointer<UserData> ptr;
  final bool _ownsMemory;

  User(this.ptr, {bool owns = false}) : _ownsMemory = owns;

  factory User.allocate(Allocator allocator) =>
      User(allocator<UserData>(), owns: true);

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

  void dispose() {
    if (_ownsMemory) calloc.free(ptr);
  }
}
