import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/lunar_calendar.dart';

void main() {
  group('lunarToSolar', () {
    test('七夕公历日期：2024/2025/2026/2027', () {
      expect(
        lunarToSolar(const LunarDate(year: 2024, month: 7, day: 7)),
        DateTime.utc(2024, 8, 10),
      );
      expect(
        lunarToSolar(const LunarDate(year: 2025, month: 7, day: 7)),
        DateTime.utc(2025, 8, 29),
      );
      expect(
        lunarToSolar(const LunarDate(year: 2026, month: 7, day: 7)),
        DateTime.utc(2026, 8, 19),
      );
      expect(
        lunarToSolar(const LunarDate(year: 2027, month: 7, day: 7)),
        DateTime.utc(2027, 8, 8),
      );
    });

    test('边界年份 2000 与 2100 可换算', () {
      expect(
        lunarToSolar(const LunarDate(year: 2000, month: 7, day: 7)),
        DateTime.utc(2000, 8, 6),
      );
      expect(
        lunarToSolar(const LunarDate(year: 2100, month: 7, day: 7)),
        DateTime.utc(2100, 8, 12),
      );
    });

    test('超出 2000–2100 返回 null', () {
      expect(
        lunarToSolar(const LunarDate(year: 1999, month: 7, day: 7)),
        isNull,
      );
      expect(
        lunarToSolar(const LunarDate(year: 2101, month: 7, day: 7)),
        isNull,
      );
    });

    test('非法月日返回 null', () {
      expect(
        lunarToSolar(const LunarDate(year: 2024, month: 13, day: 1)),
        isNull,
      );
      expect(
        lunarToSolar(const LunarDate(year: 2024, month: 0, day: 1)),
        isNull,
      );
      expect(
        lunarToSolar(const LunarDate(year: 2024, month: 2, day: 31)),
        isNull,
      );
      expect(
        lunarToSolar(const LunarDate(year: 2024, month: 7, day: 0)),
        isNull,
      );
    });
  });

  group('isLunarFestivalToday', () {
    test('七夕当天为 true，前后一天为 false', () {
      expect(isLunarFestivalToday(DateTime(2024, 8, 10), 7, 7), isTrue);
      expect(isLunarFestivalToday(DateTime(2024, 8, 9), 7, 7), isFalse);
      expect(isLunarFestivalToday(DateTime(2024, 8, 11), 7, 7), isFalse);
    });

    test('非七夕公历日期返回 false', () {
      expect(isLunarFestivalToday(DateTime(2024, 8, 5), 7, 7), isFalse);
      expect(isLunarFestivalToday(DateTime(2025, 8, 28), 7, 7), isFalse);
    });
  });
}
