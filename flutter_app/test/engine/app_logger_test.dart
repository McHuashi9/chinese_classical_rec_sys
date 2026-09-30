import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';
import 'package:chinese_classical_rec_sys/engine/app_logger.dart';

void main() {
  late DebugPrintCallback originalDebugPrint;
  late List<String> printed;

  /// 用一次性 sink 回放并清空缓冲，保证用例之间互不影响。
  void drainPending() {
    AppLogger().sinkOverride = (_, __) {};
    AppLogger().flushPending();
    AppLogger().sinkOverride = null;
  }

  setUp(() {
    // 生产环境由 main.dart 在引擎就绪后回放；测试默认桥为 null。
    NativeBridge.instance = null;
    originalDebugPrint = debugPrint;
    printed = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) printed.add(message);
    };
    drainPending();
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
    AppLogger().sinkOverride = null;
    drainPending();
  });

  group('桥未就绪（A2）', () {
    test('走 debugPrint，同时进入内存缓冲', () {
      AppLogger().warn('FFI load failed');

      expect(printed, contains('[WARN] FFI load failed'));
      expect(AppLogger().pendingCount, 1);
    });

    test('级别映射为 DEBUG/INFO/WARN/ERROR', () {
      AppLogger().debug('d');
      AppLogger().info('i');
      AppLogger().warn('w');
      AppLogger().error('e');

      expect(printed, [
        '[DEBUG] d',
        '[INFO] i',
        '[WARN] w',
        '[ERROR] e',
      ]);
    });

    test('通道未就绪时 flushPending 保留缓冲、不回放', () {
      AppLogger().info('a');
      AppLogger().debug('b');

      AppLogger().flushPending();

      expect(AppLogger().pendingCount, 2);
    });
  });

  group('桥就绪（A2 回放）', () {
    test('通道就绪时直接写入，不进缓冲也不 debugPrint', () {
      final delivered = <String>[];
      AppLogger().sinkOverride =
          (level, message) => delivered.add('$level:$message');

      AppLogger().info('hello');

      expect(delivered, ['1:hello']);
      expect(AppLogger().pendingCount, 0);
      expect(printed, isEmpty);
    });

    test('回放保持入队顺序并清空缓冲', () {
      AppLogger().error('e1');
      AppLogger().info('i2');
      final replayed = <String>[];
      AppLogger().sinkOverride =
          (level, message) => replayed.add('$level:$message');

      AppLogger().flushPending();

      expect(replayed, ['3:e1', '1:i2']);
      expect(AppLogger().pendingCount, 0);
    });

    test('回放失败静默丢弃，不影响调用方', () {
      AppLogger().info('a');
      AppLogger().sinkOverride = (_, __) => throw StateError('replay boom');

      expect(AppLogger().flushPending, returnsNormally);
      expect(AppLogger().pendingCount, 0);
    });
  });

  group('异常隔离（A1）', () {
    test('底层写入抛错时异常不外抛、不污染缓冲', () {
      AppLogger().sinkOverride = (_, __) => throw StateError('boom');

      expect(() => AppLogger().error('x'), returnsNormally);
      expect(AppLogger().pendingCount, 0);
      expect(printed.single, startsWith('[ERROR] (日志写入失败'));
    });
  });

  group('内存环形缓冲上限（A2）', () {
    test('超过 $kAppLoggerPendingCapacity 条时丢弃最旧，回放只含最近 $kAppLoggerPendingCapacity 条',
        () {
      const total = kAppLoggerPendingCapacity + 50;
      for (var i = 0; i < total; i++) {
        AppLogger().info('m$i');
      }
      expect(AppLogger().pendingCount, kAppLoggerPendingCapacity);

      final replayed = <(int, String)>[];
      AppLogger().sinkOverride =
          (level, message) => replayed.add((level, message));

      AppLogger().flushPending();

      expect(replayed.length, kAppLoggerPendingCapacity);
      expect(replayed.first.$2, 'm50');
      expect(replayed.last.$2, 'm${total - 1}');
      expect(replayed.every((entry) => entry.$1 == 1), isTrue);
      expect(AppLogger().pendingCount, 0);
    });
  });
}
