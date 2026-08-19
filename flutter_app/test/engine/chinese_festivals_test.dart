import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/chinese_festivals.dart';

void main() {
  group('农历节日注册表', () {
    test('七夕登记为农历七月初七', () {
      final festival = festivalForToday(DateTime(2024, 8, 10));
      expect(festival, isNotNull);
      expect(festival!.id, 'qixi');
      expect(festival.lunarMonth, 7);
      expect(festival.lunarDay, 7);
      expect(festival.title, '七夕快乐');
      expect(festival.content, contains('金风玉露一相逢'));
    });

    test('七夕当天返回节日', () {
      expect(festivalForToday(DateTime(2024, 8, 10))?.id, 'qixi');
      expect(festivalForToday(DateTime(2025, 8, 29))?.id, 'qixi');
      expect(festivalForToday(DateTime(2026, 8, 19))?.id, 'qixi');
      expect(festivalForToday(DateTime(2027, 8, 8))?.id, 'qixi');
    });

    test('非七夕当天返回 null', () {
      expect(festivalForToday(DateTime(2024, 8, 9)), isNull);
      expect(festivalForToday(DateTime(2024, 8, 11)), isNull);
      expect(festivalForToday(DateTime(2024, 2, 14)), isNull);
    });
  });
}
