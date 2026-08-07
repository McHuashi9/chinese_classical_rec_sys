import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/db_version.dart';

void main() {
  group('compareDbVersions', () {
    test('新格式时间前缀决定新旧', () {
      expect(compareDbVersions('202608081530-abc', '202608081529-def'), greaterThan(0));
      expect(compareDbVersions('202608081529-def', '202608081530-abc'), lessThan(0));
    });

    test('跨日期：数值比较生效', () {
      expect(compareDbVersions('202608101200-aaa', '202608081530-bbb'), greaterThan(0));
    });

    test('旧格式（YYYYMMDD-hash）与新格式可比（定长前缀字典序兼容）', () {
      expect(compareDbVersions('202608081530-aaa', '20260608-1c84aab'), greaterThan(0));
      expect(compareDbVersions('20260808-aaa', '202608081530-bbb'), lessThan(0));
      expect(compareDbVersions('202608081530-aaa', '20260808-bbb'), greaterThan(0));
    });

    test('旧格式之间按日期比较', () {
      expect(compareDbVersions('20260701-aaa', '20260608-bbb'), greaterThan(0));
      expect(compareDbVersions('20260608-bbb', '20260701-aaa'), lessThan(0));
    });

    test('完全相等返回 0', () {
      expect(compareDbVersions('20260808-1c84aab', '20260808-1c84aab'), 0);
      expect(compareDbVersions('202608081530-1c84aab', '202608081530-1c84aab'), 0);
    });

    test('同日同分不同 hash：确定性兜底（字典序），不会 0', () {
      expect(compareDbVersions('202608081530-aaa', '202608081530-bbb'), lessThan(0));
      expect(compareDbVersions('202608081530-bbb', '202608081530-aaa'), greaterThan(0));
    });

    test('不可解析版本视为最旧', () {
      expect(compareDbVersions('20260808-abc', 'unknown'), greaterThan(0));
      expect(compareDbVersions('unknown', '20260808-abc'), lessThan(0));
      expect(compareDbVersions('unknown', 'unknown'), 0);
      expect(compareDbVersions('20260808-abc', ''), greaterThan(0));
      expect(compareDbVersions('garbage', 'garbage'), 0);
      expect(compareDbVersions('garbage', '20260808-abc'), lessThan(0));
    });

    test('前后空白容忍', () {
      expect(compareDbVersions('  20260808-abc  ', '20260808-abc'), 0);
    });

    test('大小写 hash 视为不同但可比', () {
      expect(compareDbVersions('20260808-ABC', '20260808-abc'), lessThan(0));
    });

    test('仅接受 8 位或 12 位时间前缀，其余位数视为最旧（宁可降级不误判新）', () {
      expect(compareDbVersions('20260808153-abc', '202608081530-abc'), lessThan(0));
      expect(compareDbVersions('20260808153012-abc', '20260808-abc'), lessThan(0));
      expect(compareDbVersions('202608081530-abc', '2026080815-abc'), greaterThan(0));
      expect(compareDbVersions('2026080815-abc', '202608081530-abc'), lessThan(0));
    });
  });

  group('isDbNewer', () {
    test('严格更新才返回 true', () {
      expect(isDbNewer('202608081530-aaa', '202608081529-bbb'), isTrue);
      expect(isDbNewer('202608081529-bbb', '202608081530-aaa'), isFalse);
      expect(isDbNewer('202608081530-aaa', '202608081530-aaa'), isFalse);
      expect(isDbNewer('20260808-aaa', '202608081530-bbb'), isFalse);
      expect(isDbNewer('unknown', '202608081530-aaa'), isFalse);
    });
  });
}