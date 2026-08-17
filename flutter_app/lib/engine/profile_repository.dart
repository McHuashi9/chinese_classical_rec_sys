import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';
import 'package:chinese_classical_rec_sys/models/user_profile.dart';

/// 档案名字节上限（C 侧 name[64]，保留 1 字节 NUL；约 21 个汉字）
const int maxProfileNameBytes = 63;

/// 档案数上限（未删除档案，含默认档案）——与 C++ kMaxProfiles 同步；
/// 设置页满员时禁用新建按钮（C++ 侧同样拒绝，双保险）
const int kMaxProfiles = 32;

/// 档案 FFI 抽象：UserController 依赖此接口（生产注入 [FfiProfileRepository]，
/// 测试注入 Fake）。
abstract class ProfileRepository {
  List<UserProfile> listProfiles();
  int activeUserId();
  int? createProfile(String name);
  int? createProfileInherit(String name, int sourceId);
  bool switchProfile(int id);
  bool renameProfile(int id, String name);
  bool deleteProfile(int id);
}

/// 档案 FFI 封装
class FfiProfileRepository implements ProfileRepository {
  final NativeBridge _bridge;

  FfiProfileRepository(this._bridge);

  @override
  List<UserProfile> listProfiles() {
    const cap = 50;
    final block = calloc<ProfileData>(cap);
    final n = _bridge.userList(block, cap);
    if (n <= 0) {
      calloc.free(block);
      return [];
    }
    final count = n < cap ? n : cap;
    final profiles = <UserProfile>[
      for (int i = 0; i < count; i++)
        UserProfile(
          id: (block + i).ref.id,
          name: readCString((block + i).ref.name, 64),
          createdAt: (block + i).ref.createdAt,
          lastUsedAt: (block + i).ref.lastUsedAt,
        ),
    ];
    calloc.free(block);
    return profiles;
  }

  @override
  int activeUserId() => _bridge.userActiveId();

  @override
  int? createProfile(String name) {
    final ptr = name.toNativeUtf8(allocator: calloc);
    final rc = _bridge.userCreate(ptr);
    calloc.free(ptr);
    return rc > 0 ? rc : null;
  }

  @override
  int? createProfileInherit(String name, int sourceId) {
    final ptr = name.toNativeUtf8(allocator: calloc);
    final rc = _bridge.userCreateInherit(ptr, sourceId);
    calloc.free(ptr);
    return rc > 0 ? rc : null;
  }

  @override
  bool switchProfile(int id) => _bridge.userSwitch(id) == BridgeError.ok;

  @override
  bool renameProfile(int id, String name) {
    final ptr = name.toNativeUtf8(allocator: calloc);
    final rc = _bridge.userRename(id, ptr);
    calloc.free(ptr);
    return rc == BridgeError.ok;
  }

  @override
  bool deleteProfile(int id) => _bridge.userDelete(id) == BridgeError.ok;
}

/// 校验并规范化档案名：返回 null 表示非法（空 / 超字节上限）。
String? normalizeProfileName(String input) {
  final name = input.trim();
  if (name.isEmpty) return null;
  if (utf8.encode(name).length > maxProfileNameBytes) return null;
  return name;
}
