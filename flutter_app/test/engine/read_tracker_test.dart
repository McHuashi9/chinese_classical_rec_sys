import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';

void main() {
  group('ReadTracker', () {
    late ReadTracker tracker;

    setUp(() {
      tracker = ReadTracker();
    });

    group('初始状态', () {
      test('isTextRead 对未知 id 返回 false', () {
        expect(tracker.isTextRead(1), false);
        expect(tracker.isTextRead(9999), false);
      });

      test('hasUnrecordedReading 对 null 返回 false', () {
        expect(tracker.hasUnrecordedReading(null), false);
      });

      test('hasUnrecordedReading 对未知 id 返回 false', () {
        expect(tracker.hasUnrecordedReading(1), false);
      });

      test('totalSecondsFor 对未知 id 返回 0', () {
        expect(tracker.totalSecondsFor(1), 0);
      });

      test('getAllTrackedIds 在空状态返回空列表', () {
        expect(tracker.getAllTrackedIds(), isEmpty);
      });
    });

    group('saveDuration', () {
      test('设置并读取 totalSeconds', () {
        tracker.saveDuration(1, 120);
        expect(tracker.totalSecondsFor(1), 120);
      });

      test('覆盖已有 duration', () {
        tracker.saveDuration(1, 60);
        tracker.saveDuration(1, 180);
        expect(tracker.totalSecondsFor(1), 180);
      });

      test('仅保存 duration 不影响 isTextRead', () {
        tracker.saveDuration(1, 100);
        expect(tracker.isTextRead(1), false);
      });
    });

    group('markEffectApplied', () {
      test('标记后 isTextRead 返回 true', () {
        tracker.markEffectApplied(1);
        expect(tracker.isTextRead(1), true);
      });

      test('标记后 hasUnrecordedReading 返回 false', () {
        tracker.ensureState(1);
        expect(tracker.hasUnrecordedReading(1), true);
        tracker.markEffectApplied(1);
        expect(tracker.hasUnrecordedReading(1), false);
      });

      test('标记后计时值仍保留', () {
        tracker.saveDuration(1, 300);
        tracker.markEffectApplied(1);
        expect(tracker.totalSecondsFor(1), 300);
        expect(tracker.isTextRead(1), true);
      });
    });

    group('ensureState', () {
      test('创建条目且 isTextRead 为 false', () {
        tracker.ensureState(1);
        expect(tracker.isTextRead(1), false);
        expect(tracker.hasUnrecordedReading(1), true);
      });

      test('幂等调用不覆盖已有数据', () {
        tracker.markEffectApplied(1);
        tracker.ensureState(1);
        expect(tracker.isTextRead(1), true);
      });
    });

    group('loadFromIds', () {
      test('全部标记为 tracked', () {
        tracker.loadFromIds([1, 2, 3]);
        expect(tracker.isTextRead(1), true);
        expect(tracker.isTextRead(2), true);
        expect(tracker.isTextRead(3), true);
      });

      test('空列表安全', () {
        tracker.loadFromIds([]);
        expect(tracker.getAllTrackedIds(), isEmpty);
      });
    });

    group('getAllTrackedIds', () {
      test('仅返回 effectApplied 的 id', () {
        tracker.markEffectApplied(1);
        tracker.saveDuration(2, 10);
        tracker.markEffectApplied(3);
        final ids = tracker.getAllTrackedIds();
        expect(ids, containsAll([1, 3]));
        expect(ids, isNot(contains(2)));
      });

      test('loadFromIds 后的 id 都在 tracked 中', () {
        tracker.loadFromIds([5, 10, 15]);
        final ids = tracker.getAllTrackedIds();
        expect(ids.length, 3);
        expect(ids, containsAll([5, 10, 15]));
      });
    });

    group('容量上限', () {
      test('超过 500 条目时淘汰最早插入的', () {
        for (int i = 0; i < 510; i++) {
          tracker.ensureState(i);
        }
        // earliest entries should be evicted
        expect(tracker.isTextRead(0), false);
        expect(tracker.isTextRead(9), false);
        // newer entries should still be present
        expect(tracker.isTextRead(509), false);
        expect(tracker.hasUnrecordedReading(509), true);
      });

      test('淘汰后 tracked id 随之移除', () {
        tracker.markEffectApplied(1);
        for (int i = 2; i < 520; i++) {
          tracker.ensureState(i);
        }
        expect(tracker.getAllTrackedIds(), isNot(contains(1)));
      });

      test('saveDuration 也触发淘汰', () {
        for (int i = 0; i < 510; i++) {
          tracker.saveDuration(i, i * 10);
        }
        // entries 0-9 should be gone
        expect(tracker.totalSecondsFor(0), 0);
        expect(tracker.totalSecondsFor(9), 0);
        // entry 509 still present
        expect(tracker.totalSecondsFor(509), 509 * 10);
      });
    });

    group('边界情况', () {
      test('同一 id 多种操作组合', () {
        tracker.loadFromIds([1]);
        expect(tracker.isTextRead(1), true);

        tracker.saveDuration(1, 60);
        expect(tracker.totalSecondsFor(1), 60);
        expect(tracker.isTextRead(1), true);
      });

      test('markEffectApplied 在 loadFromIds 后不覆盖', () {
        tracker.loadFromIds([1]);
        tracker.markEffectApplied(1);
        expect(tracker.isTextRead(1), true);
      });

      test('重复 save + mark 保持一致性', () {
        tracker.saveDuration(1, 10);
        tracker.markEffectApplied(1);
        tracker.saveDuration(1, 20);
        tracker.markEffectApplied(1);

        expect(tracker.isTextRead(1), true);
        expect(tracker.totalSecondsFor(1), 20);
        expect(tracker.hasUnrecordedReading(1), false);
      });
    });
  });
}
