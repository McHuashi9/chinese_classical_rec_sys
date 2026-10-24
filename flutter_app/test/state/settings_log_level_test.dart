import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsController.normalizeLogLevel（A5 白名单归一）', () {
    test('白名单四档原样保留，大小写不敏感', () {
      for (final level in SettingsController.logLevelOptions) {
        expect(SettingsController.normalizeLogLevel(level), level);
        expect(
          SettingsController.normalizeLogLevel(level.toLowerCase()),
          level,
          reason: '小写 $level 也应归一到白名单大写，否则设置页下拉匹配不到',
        );
      }
    });

    test('null / 空白 / 非法值回退 INFO', () {
      for (final dirty in [null, '', '  ', 'verbose', 'TRACE', 'debug2', '日志']) {
        expect(
          SettingsController.normalizeLogLevel(dirty),
          SettingsController.defaultLogLevel,
          reason: '脏值“$dirty”应回退到 ${SettingsController.defaultLogLevel}',
        );
      }
    });

    test('白名单即设置页下拉取值域（顺序单一源）', () {
      expect(
        SettingsController.logLevelOptions,
        ['INFO', 'DEBUG', 'WARN', 'ERROR'],
      );
    });
  });

  group('SettingsController 脏 prefs 免疫（A5）', () {
    Future<SettingsController> initWith(Map<String, Object> prefsValues) async {
      SharedPreferences.setMockInitialValues(prefsValues);
      final prefs = await SharedPreferences.getInstance();
      final ctrl = SettingsController();
      addTearDown(ctrl.dispose);
      await ctrl.init(prefs, null);
      return ctrl;
    }

    test('非法 logLevel → 归一为 INFO', () async {
      final ctrl = await initWith({'logLevel': 'verbose'});
      expect(ctrl.logLevel, 'INFO');
    });

    test('小写合法 logLevel → 归一为白名单大写', () async {
      final ctrl = await initWith({'logLevel': 'debug'});
      expect(ctrl.logLevel, 'DEBUG');
    });

    test('缺失 logLevel → 默认 INFO', () async {
      final ctrl = await initWith({});
      expect(ctrl.logLevel, 'INFO');
    });

    test('setLogLevel 归一后同时更新内存值与 prefs（脏输入不落库）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final ctrl = SettingsController();
      addTearDown(ctrl.dispose);
      await ctrl.init(prefs, null);

      ctrl.setLogLevel('verbose');
      expect(ctrl.logLevel, 'INFO');
      expect(prefs.getString('logLevel'), 'INFO');

      ctrl.setLogLevel('debug');
      expect(ctrl.logLevel, 'DEBUG');
      expect(prefs.getString('logLevel'), 'DEBUG');
    });
  });
}
