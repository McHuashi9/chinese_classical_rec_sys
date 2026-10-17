import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/app_logger.dart';
import 'package:chinese_classical_rec_sys/engine/profile_repository.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/models/user_profile.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';

class _FailingProfileRepo implements ProfileRepository {
  @override
  int? createProfile(String name) => null;

  @override
  int? createProfileInherit(String name, int sourceId) => null;

  @override
  bool deleteProfile(int id) => false;

  @override
  List<UserProfile> listProfiles() => const [];

  @override
  bool renameProfile(int id, String name) => false;

  @override
  int activeUserId() => 0;

  @override
  bool switchProfile(int id) => false;
}

void main() {
  late List<String> logs;

  setUp(() {
    logs = <String>[];
    AppLogger().sinkOverride = (level, message) => logs.add('$level:$message');
  });

  tearDown(() {
    AppLogger().sinkOverride = null;
  });

  test('UserController 失败日志只记操作/id，不记档案名', () {
    final ctrl = UserController();
    ctrl.initProfiles(_FailingProfileRepo());

    final id = ctrl.createProfile('非常敏感的档案名');
    expect(id, isNull);
    expect(logs.join('\n'), contains('createProfile 失败'));
    expect(logs.join('\n'), isNot(contains('非常敏感的档案名')));
    ctrl.dispose();
  });

  test('Coordinator 阅读效应跳过与远程同步前置失败有诊断日志', () {
    final readTracker = ReadTracker();
    final readingCtrl = ReadingController(readTracker);
    final userCtrl = UserController();
    final coord = AppCoordinator(
      navCtrl: NavigationController(),
      settingsCtrl: SettingsController(),
      readingCtrl: readingCtrl,
      userCtrl: userCtrl,
      readTracker: readTracker,
    );

    coord.applyReadingEffect();
    coord.remoteSyncDb();

    expect(logs.join('\n'), contains('applyReadingEffect 跳过'));
    expect(logs.join('\n'), contains('remoteSyncDb 跳过'));

    coord.dispose();
  });
}
