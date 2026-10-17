import 'package:chinese_classical_rec_sys/bridge/c_types.dart';

/// DB 打开失败码 → 用户可见文案。
///
/// 这是 UI/启动链唯一使用的映射；不得把原始路径或异常串拼进用户可见错误。
String dbOpenErrorMessage(int? code) {
  switch (code) {
    case BridgeError.errDbContent:
      return '内容库缺失或损坏，请重启应用。\n若持续出现，请重新安装。';
    case BridgeError.errDbUser:
      return '用户库缺失或损坏，请重启应用。\n若持续出现，请重新安装。';
    case BridgeError.errDbVersion:
      return '数据库版本不兼容，请更新应用或重新安装。';
    case BridgeError.errDbSamePath:
      return '内容库与用户库路径相同，请重启应用。';
    default:
      return '数据库打开失败，请重启应用。\n若持续出现，请重新安装。';
  }
}
