import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';

/// 错误码对拍：Dart 生成常量必须与 bridge/error_codes.def 的唯一源逐项一致。
/// 该用例不依赖原生库，CI 与本地都能跑；发现漂移时运行
/// `python3 scripts/project/generate_bridge_error_codes.py` 重新生成。
void main() {
  test('BridgeError 与 bridge/error_codes.def 唯一源对拍', () {
    final candidates = [
      File('../bridge/error_codes.def'),
      File('bridge/error_codes.def'),
    ];
    final source = candidates.where((f) => f.existsSync()).first;
    final pattern = RegExp(
      r'^\s*BRIDGE_ERROR\(\s*([A-Z][A-Z0-9_]*)\s*,\s*(-?\d+)\s*,\s*"((?:[^"\\]|\\.)*)"\s*\)\s*$',
      multiLine: true,
    );
    final entries = <(String, int, String)>[];
    for (final line in source.readAsLinesSync()) {
      final m = pattern.firstMatch(line);
      if (m != null) {
        entries.add((m.group(1)!, int.parse(m.group(2)!), m.group(3)!));
      }
    }
    expect(entries, isNotEmpty, reason: '未从 ${source.path} 解析到错误码');

    final expectedNames = <int, String>{};
    final expectedMessages = <int, String>{};
    for (final (name, code, description) in entries) {
      expectedNames[code] = 'BRIDGE_$name';
      expectedMessages[code] = description;
    }
    expect(BridgeError.names, expectedNames);
    expect(BridgeError.messages, expectedMessages);
    expect(BridgeError.ok, 0);
    expect(BridgeError.errGeneric, -1);
    expect(BridgeError.errNotInit, -2);
    expect(BridgeError.errInitIncomplete, -10);
    for (final (_, code, _) in entries) {
      expect(BridgeError.nameOf(code), expectedNames[code]);
      expect(BridgeError.messageOf(code), expectedMessages[code]);
    }
  });
}
