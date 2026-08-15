import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/profile_repository.dart';
import 'package:chinese_classical_rec_sys/models/user_profile.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';

/// 可编排 Fake：档案列表/操作按内存状态模拟
class _FakeProfileRepository implements ProfileRepository {
  final List<UserProfile> profiles = [];
  int activeId = 1;
  int nextId = 2;
  bool failCreate = false;
  bool failRename = false;
  bool failDelete = false;

  @override
  List<UserProfile> listProfiles() => List.of(profiles);

  @override
  int activeUserId() => activeId;

  @override
  int? createProfile(String name) {
    if (failCreate) return null;
    final id = nextId++;
    profiles.add(UserProfile(
        id: id, name: name, createdAt: 1000 + id, lastUsedAt: 2000 + id));
    return id;
  }

  @override
  bool switchProfile(int id) {
    if (!profiles.any((p) => p.id == id)) return false;
    activeId = id;
    return true;
  }

  @override
  bool renameProfile(int id, String name) {
    if (failRename) return false;
    final idx = profiles.indexWhere((p) => p.id == id);
    if (idx < 0) return false;
    profiles[idx] = UserProfile(
        id: id,
        name: name,
        createdAt: profiles[idx].createdAt,
        lastUsedAt: profiles[idx].lastUsedAt);
    return true;
  }

  @override
  bool deleteProfile(int id) {
    if (failDelete) return false;
    final idx = profiles.indexWhere((p) => p.id == id);
    if (idx < 0) return false;
    profiles.removeAt(idx);
    return true;
  }
}

void main() {
  group('UserController 档案状态', () {
    late UserController ctrl;
    late _FakeProfileRepository repo;

    setUp(() {
      ctrl = UserController();
      repo = _FakeProfileRepository();
      repo.profiles.add(const UserProfile(
          id: 1, name: '默认用户', createdAt: 1001, lastUsedAt: 2001));
      ctrl.initProfiles(repo);
    });

    tearDown(() => ctrl.dispose());

    test('refreshProfiles 拉取列表并解析当前档案名', () {
      var notified = 0;
      ctrl.addListener(() => notified++);

      expect(ctrl.refreshProfiles(), isTrue);
      expect(ctrl.profiles.length, 1);
      expect(ctrl.profiles.first.name, '默认用户');
      expect(ctrl.activeUserId, 1);
      expect(ctrl.activeProfileName, '默认用户');
      expect(notified, 1);
    });

    test('未注入仓库时 refreshProfiles 返回 false', () {
      final bare = UserController();
      expect(bare.refreshProfiles(), isFalse);
      expect(bare.profiles, isEmpty);
      bare.dispose();
    });

    test('createProfile 规范化名称并刷新列表', () {
      ctrl.refreshProfiles();
      final id = ctrl.createProfile('  小明  ');
      expect(id, 2);
      expect(ctrl.profiles.length, 2);
      expect(ctrl.profiles.last.name, '小明');
    });

    test('createProfile 非法名称返回 null', () {
      ctrl.refreshProfiles();
      expect(ctrl.createProfile('   '), isNull);
      expect(ctrl.createProfile('长' * 100), isNull);
    });

    test('renameProfile 更新列表中的档案名', () {
      ctrl.refreshProfiles();
      expect(ctrl.renameProfile(1, '小红'), isTrue);
      expect(ctrl.profiles.first.name, '小红');
    });

    test('deleteProfile 删除后列表刷新', () {
      ctrl.refreshProfiles();
      expect(ctrl.deleteProfile(1), isTrue);
      expect(ctrl.profiles, isEmpty);
    });
  });
}
