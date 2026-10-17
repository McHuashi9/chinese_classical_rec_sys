// GENERATED CODE - DO NOT EDIT.
// 唯一源: bridge/error_codes.def
// 重新生成: python3 scripts/project/generate_bridge_error_codes.py

/// C ABI 错误码（数值与名称均从 [bridge/error_codes.def] 生成）。
abstract final class BridgeError {
  static const int ok = 0;
  static const int errGeneric = -1;
  static const int errNotInit = -2;
  static const int errUser = -3;
  static const int errText = -4;
  static const int errInit = -5;
  static const int errDbContent = -6;
  static const int errDbUser = -7;
  static const int errDbVersion = -8;
  static const int errDbSamePath = -9;
  static const int errInitIncomplete = -10;

  /// code -> 稳定符号名，用于日志/异常文本。
  static const Map<int, String> names = {
    0: 'BRIDGE_OK',
    -1: 'BRIDGE_ERR_GENERIC',
    -2: 'BRIDGE_ERR_NOT_INIT',
    -3: 'BRIDGE_ERR_USER',
    -4: 'BRIDGE_ERR_TEXT',
    -5: 'BRIDGE_ERR_INIT',
    -6: 'BRIDGE_ERR_DB_CONTENT',
    -7: 'BRIDGE_ERR_DB_USER',
    -8: 'BRIDGE_ERR_DB_VERSION',
    -9: 'BRIDGE_ERR_DB_SAME_PATH',
    -10: 'BRIDGE_ERR_INIT_INCOMPLETE',
  };

  /// code -> 中文说明。
  static const Map<int, String> messages = {
    0: "成功",
    -1: "通用错误",
    -2: "未初始化（未调用 db_open）",
    -3: "用户/档案不存在或不可用",
    -4: "文本/题目不存在",
    -5: "初始化失败",
    -6: "内容库缺失/损坏/缺表/含旧用户表",
    -7: "用户库缺失/损坏",
    -8: "db_version 不兼容（0 或 >1）",
    -9: "user.db 与 classical.db 同路径",
    -10: "强制初始化未完成",
  };

  static String nameOf(int code) => names[code] ?? 'BRIDGE_ERR_UNKNOWN($code)';
  static String messageOf(int code) => messages[code] ?? '未知错误';
}
