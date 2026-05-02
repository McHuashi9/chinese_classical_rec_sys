import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'c_types.dart';

/// Dart FFI 函数表 — 绑定 libchinese_core.so 的所有 C 函数
final class NativeBridge {
  final DynamicLibrary _lib;

  // ─── 生命周期 ────────────────────────────────────────────────
  late final int Function(Pointer<Utf8> dbPath) dbOpen;
  late final void Function() dbClose;

  // ─── 用户 ────────────────────────────────────────────────────
  late final int Function(Pointer<UserData> out) userLoad;
  late final int Function(Pointer<UserData> inp) userSave;
  late final int Function() userInitDefault;

  // ─── 文本 ────────────────────────────────────────────────────
  late final int Function() textGetCount;
  late final void Function(Pointer<TextInfo> out, int maxCount) textGetAll;
  late final int Function(int id, Pointer<TextDetail> out) textGetDetail;

  // ─── 推荐 ────────────────────────────────────────────────────
  late final int Function(
    Pointer<UserData> user,
    int topK,
    Pointer<Int32> outIds,
    Pointer<Double> outProbs,
  ) recommend;

  // ─── 知识追踪 ────────────────────────────────────────────────
  late final int Function(
    Pointer<UserData> user,
    int textId,
    double readTime,
    int timestamp,
    Pointer<UserData> outUser,
  ) trackerApplyRead;

  late final int Function(
    Pointer<UserData> user,
    int now,
    Pointer<UserData> outUser,
  ) trackerApplyForgetting;

  late final int Function(
    Pointer<UserData> user,
    int now,
    Pointer<UserData> outUser,
  ) trackerPrune;

  // ──────────────────────────────────────────────────────────────

  NativeBridge(String libPath) : _lib = DynamicLibrary.open(libPath) {
    dbOpen = _lib.lookupFunction<
        Int32 Function(Pointer<Utf8>),
        int Function(Pointer<Utf8>)>('db_open');

    dbClose = _lib.lookupFunction<
        Void Function(),
        void Function()>('db_close');

    userLoad = _lib.lookupFunction<
        Int32 Function(Pointer<UserData>),
        int Function(Pointer<UserData>)>('user_load');

    userSave = _lib.lookupFunction<
        Int32 Function(Pointer<UserData>),
        int Function(Pointer<UserData>)>('user_save');

    userInitDefault = _lib.lookupFunction<
        Int32 Function(),
        int Function()>('user_init_default');

    textGetCount = _lib.lookupFunction<
        Int32 Function(),
        int Function()>('text_get_count');

    textGetAll = _lib.lookupFunction<
        Void Function(Pointer<TextInfo>, Int32),
        void Function(Pointer<TextInfo>, int)>('text_get_all');

    textGetDetail = _lib.lookupFunction<
        Int32 Function(Int32, Pointer<TextDetail>),
        int Function(int, Pointer<TextDetail>)>('text_get_detail');

    recommend = _lib.lookupFunction<
        Int32 Function(Pointer<UserData>, Int32, Pointer<Int32>, Pointer<Double>),
        int Function(Pointer<UserData>, int, Pointer<Int32>, Pointer<Double>)>(
            'recommend');

    trackerApplyRead = _lib.lookupFunction<
        Int32 Function(Pointer<UserData>, Int32, Double, Int64, Pointer<UserData>),
        int Function(Pointer<UserData>, int, double, int, Pointer<UserData>)>(
            'tracker_apply_read');

    trackerApplyForgetting = _lib.lookupFunction<
        Int32 Function(Pointer<UserData>, Int64, Pointer<UserData>),
        int Function(Pointer<UserData>, int, Pointer<UserData>)>(
            'tracker_apply_forgetting');

    trackerPrune = _lib.lookupFunction<
        Int32 Function(Pointer<UserData>, Int64, Pointer<UserData>),
        int Function(Pointer<UserData>, int, Pointer<UserData>)>(
            'tracker_prune');
  }
}
