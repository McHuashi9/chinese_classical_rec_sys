import 'package:chinese_classical_rec_sys/bridge/c_types.dart';

import 'app_logger.dart';

/// FFI 业务错误（Dart 引擎层统一异常类型）。
///
/// 契约：NativeBridge 返回负错误码时，引擎封装必须抛出本异常并由本文件统一记日志；
/// 返回 0/正数才是正常结果（空列表 = 成功但无数据，绝不与失败混用）。
class FfiException implements Exception {
  final String operation;
  final int code;

  const FfiException({required this.operation, required this.code});

  String get codeName => BridgeError.nameOf(code);
  String get description => BridgeError.messageOf(code);

  @override
  String toString() => 'FFI $operation 失败: $codeName ($code) $description';
}

/// 校验“成功 / 失败”型 C 返回码。
int requireBridgeOk(int rc, String operation) {
  if (rc == BridgeError.ok) return rc;
  throw _fail(rc, operation);
}

/// 校验“计数 / 列表长度”型 C 返回码：0 与正数都是成功，负数才是失败。
int requireBridgeCount(int rc, String operation) {
  if (rc >= 0) return rc;
  throw _fail(rc, operation);
}

Never _fail(int rc, String operation) {
  final error = FfiException(operation: operation, code: rc);
  final message = '$operation: ${error.codeName} ($rc) ${error.description}';
  if (rc == BridgeError.errText || rc == BridgeError.errUser) {
    AppLogger().warn('FFI 失败（业务拒绝）— $message');
  } else {
    AppLogger().error('FFI 失败 — $message');
  }
  throw error;
}
