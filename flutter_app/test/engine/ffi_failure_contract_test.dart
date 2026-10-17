import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/engine/app_logger.dart';
import 'package:chinese_classical_rec_sys/engine/ffi_call.dart';

void main() {
  setUp(() {
    AppLogger().sinkOverride = (_, __) {};
  });
  tearDown(() {
    AppLogger().sinkOverride = null;
  });

  group('FFI 失败契约', () {
    test('成功码不抛异常；计数 0 与正数都表示成功', () {
      expect(requireBridgeOk(BridgeError.ok, 'ok'), BridgeError.ok);
      expect(requireBridgeCount(0, 'count'), 0);
      expect(requireBridgeCount(3, 'count'), 3);
    });

    test('失败码抛 FfiException 并带稳定符号名/中文说明', () {
      expect(
        () => requireBridgeOk(BridgeError.errNotInit, 'user_load'),
        throwsA(
          isA<FfiException>()
              .having((e) => e.code, 'code', BridgeError.errNotInit)
              .having((e) => e.operation, 'operation', 'user_load')
              .having((e) => e.codeName, 'codeName', 'BRIDGE_ERR_NOT_INIT')
              .having((e) => e.toString(), 'toString',
                  contains('BRIDGE_ERR_NOT_INIT')),
        ),
      );
      expect(
        () => requireBridgeCount(BridgeError.errGeneric, 'quiz_count'),
        throwsA(isA<FfiException>()
            .having((e) => e.code, 'code', BridgeError.errGeneric)),
      );
    });

    test('失败统一记日志（不静默吞掉）', () {
      final logs = <String>[];
      AppLogger().sinkOverride = (level, message) => logs.add(message);
      expect(
        () => requireBridgeCount(BridgeError.errGeneric, 'quiz_count'),
        throwsA(isA<FfiException>()),
      );
      expect(logs, hasLength(1));
      expect(logs.single, contains('quiz_count'));
      expect(logs.single, contains('BRIDGE_ERR_GENERIC'));
    });
  });
}
