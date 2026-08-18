import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/chinese_festivals.dart';

void main() {
  group('七夕节日注册', () {
    test('七夕为农历七月初七', () {
      expect(qixiMonth, 7);
      expect(qixiDay, 7);
    });

    test('七夕当天返回 true', () {
      expect(isQixiToday(DateTime(2024, 8, 10)), isTrue);
      expect(isQixiToday(DateTime(2025, 8, 29)), isTrue);
      expect(isQixiToday(DateTime(2026, 8, 19)), isTrue);
      expect(isQixiToday(DateTime(2027, 8, 8)), isTrue);
    });

    test('非七夕当天返回 false', () {
      expect(isQixiToday(DateTime(2024, 8, 9)), isFalse);
      expect(isQixiToday(DateTime(2024, 8, 11)), isFalse);
      expect(isQixiToday(DateTime(2024, 2, 14)), isFalse);
    });
  });
}
