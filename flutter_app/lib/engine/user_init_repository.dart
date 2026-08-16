import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';

/// 强制初始化 FFI 抽象：UserController 依赖此接口（生产注入
/// [FfiUserInitRepository]，测试注入 Fake）。
abstract class UserInitRepository {
  /// 当前档案是否已完成强制初始化。
  bool isInitialized();

  /// 返回 6 道初始化题（整块内存，用后必须 [disposeInitQuestions] 释放）。
  List<Question> initQuestions();

  /// 释放 [initQuestions] 返回的题组内存（恰好一次）。
  void disposeInitQuestions(List<Question> questions);

  /// 提交初始化题：成功返回新 User（所有权转移给调用方），失败返回 null。
  User? applyInit(List<int> qids, List<int> choices);
}

/// 用户初始化 FFI 封装
class FfiUserInitRepository implements UserInitRepository {
  final NativeBridge _bridge;
  static const int initQuestionCap = 8;

  FfiUserInitRepository(this._bridge);

  @override
  bool isInitialized() => _bridge.userIsInitialized() > 0;

  @override
  List<Question> initQuestions() {
    final block = calloc<QuestionData>(initQuestionCap);
    final n = _bridge.userInitQuestions(block, initQuestionCap);
    if (n <= 0) {
      calloc.free(block);
      return [];
    }
    final count = n < initQuestionCap ? n : initQuestionCap;
    return [for (int i = 0; i < count; i++) Question(block + i, owner: block)];
  }

  @override
  void disposeInitQuestions(List<Question> questions) {
    if (questions.isEmpty) return;
    calloc.free(questions.first.owner);
  }

  @override
  User? applyInit(List<int> qids, List<int> choices) {
    if (qids.length != choices.length || qids.isEmpty) return null;
    final qidsPtr = calloc<Int32>(qids.length);
    final choicesPtr = calloc<Int32>(choices.length);
    for (int i = 0; i < qids.length; i++) {
      qidsPtr[i] = qids[i];
      choicesPtr[i] = choices[i];
    }
    final outUser = User.allocate(calloc);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rc = _bridge.userInitApply(
        qidsPtr, choicesPtr, qids.length, now, outUser.ptr);
    calloc.free(qidsPtr);
    calloc.free(choicesPtr);
    if (rc != BridgeError.ok) {
      outUser.dispose();
      return null;
    }
    return outUser;
  }
}
