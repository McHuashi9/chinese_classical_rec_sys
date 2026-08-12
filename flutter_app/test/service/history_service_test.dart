import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/service/history_service.dart';

/// 构造本地时间某天的 timestamp（秒），避免时区偏移导致日期断言漂移
int ts(int year, int month, int day, {int hour = 10}) =>
    DateTime(year, month, day, hour).millisecondsSinceEpoch ~/ 1000;

ReadingRecord rec(int textId, double readTime, int timestamp) => ReadingRecord(
      textId: textId,
      title: '题$textId',
      author: '作者$textId',
      dynasty: '唐',
      readTime: readTime,
      timestamp: timestamp,
    );

void main() {
  group('HistoryService.computeStats', () {
    test('空列表：全零', () {
      final s = HistoryService.computeStats([]);
      expect(s.totalSeconds, 0);
      expect(s.totalTexts, 0);
      expect(s.dailyAvgSeconds, 0.0);
      expect(s.longestStreak, 0);
    });

    test('单条记录：时长/篇数/日均/连续均为 1', () {
      final s = HistoryService.computeStats([
        rec(1, 120.5, ts(2026, 8, 12)),
      ]);
      expect(s.totalSeconds, 120);
      expect(s.totalTexts, 1);
      expect(s.dailyAvgSeconds, 120.0);
      expect(s.longestStreak, 1);
    });

    test('同日多条：日均分母为天数（1 天）而非条数', () {
      final s = HistoryService.computeStats([
        rec(1, 100, ts(2026, 8, 12, hour: 8)),
        rec(2, 200, ts(2026, 8, 12, hour: 20)),
        rec(3, 300, ts(2026, 8, 12, hour: 22)),
      ]);
      expect(s.totalSeconds, 600);
      expect(s.totalTexts, 3);
      expect(s.dailyAvgSeconds, 600.0);
      expect(s.longestStreak, 1);
    });

    test('连续 3 天：最长连续 3，日均按 3 天平均', () {
      final s = HistoryService.computeStats([
        rec(1, 300, ts(2026, 8, 10)),
        rec(2, 300, ts(2026, 8, 11)),
        rec(3, 300, ts(2026, 8, 12)),
      ]);
      expect(s.longestStreak, 3);
      expect(s.dailyAvgSeconds, 300.0);
    });

    test('断档后连续重置：1,2,4 天 → 最长连续 2', () {
      final s = HistoryService.computeStats([
        rec(1, 100, ts(2026, 8, 11)),
        rec(2, 100, ts(2026, 8, 12)),
        rec(3, 100, ts(2026, 8, 14)),
      ]);
      expect(s.longestStreak, 2);
    });

    test('跨月连续：7/31 与 8/1 视为连续', () {
      final s = HistoryService.computeStats([
        rec(1, 100, ts(2026, 7, 31)),
        rec(2, 100, ts(2026, 8, 1)),
      ]);
      expect(s.longestStreak, 2);
    });

    test('同篇多条：篇数去重', () {
      final s = HistoryService.computeStats([
        rec(5, 100, ts(2026, 8, 10)),
        rec(5, 100, ts(2026, 8, 11)),
        rec(6, 100, ts(2026, 8, 12)),
      ]);
      expect(s.totalTexts, 2);
      expect(s.longestStreak, 3);
    });

    test('同日同一篇的两次阅读只算一天', () {
      final s = HistoryService.computeStats([
        rec(5, 100, ts(2026, 8, 12, hour: 8)),
        rec(5, 100, ts(2026, 8, 12, hour: 21)),
      ]);
      expect(s.totalTexts, 1);
      expect(s.dailyAvgSeconds, 200.0);
      expect(s.longestStreak, 1);
    });
  });
}
