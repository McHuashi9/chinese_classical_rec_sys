import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:chinese_classical_rec_sys/bridge/ffi_bindings.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/engine/recommendation.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';

class ReadingRecord {
  final int textId;
  final String title;
  final String author;
  final String dynasty;
  final double readTime;
  final int timestamp;
  DateTime get date => DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);

  const ReadingRecord({
    required this.textId,
    required this.title,
    required this.author,
    required this.dynasty,
    required this.readTime,
    required this.timestamp,
  });
}

class ReadingStats {
  final int totalSeconds;
  final int totalTexts;
  final double dailyAvgSeconds;
  final int longestStreak;

  const ReadingStats({
    required this.totalSeconds,
    required this.totalTexts,
    required this.dailyAvgSeconds,
    required this.longestStreak,
  });
}

class HistoryService {
  final NativeBridge _bridge;
  final RecommendationEngine _engine;

  HistoryService(this._bridge, this._engine);

  List<ReadingRecord> getRecent(int limit) {
    final ptr = calloc<ReadingRecordData>(limit);
    final count = _bridge.historyGetRecent(limit, ptr, limit);
    final records = <ReadingRecord>[];
    for (int i = 0; i < count; i++) {
      final r = ptr[i];
      final text = _engine.texts.cast<ChineseText?>().firstWhere(
        (t) => t?.id == r.textId, orElse: () => null,
      );
      records.add(ReadingRecord(
        textId: r.textId,
        title: text?.title ?? '(未知)',
        author: text?.author ?? '',
        dynasty: text?.dynasty ?? '',
        readTime: r.readTime,
        timestamp: r.timestamp,
      ));
    }
    calloc.free(ptr);
    return records;
  }

  int getTotalCount() => _bridge.historyGetTotalCount();

  ReadingStats computeStats(List<ReadingRecord> records) {
    int totalSeconds = 0;
    final dateSet = <int>{};
    for (final r in records) {
      totalSeconds += r.readTime.toInt();
      dateSet.add(DateTime(r.date.year, r.date.month, r.date.day).millisecondsSinceEpoch);
    }
    final totalTexts = records.isEmpty ? 0 : records.map((r) => r.textId).toSet().length;

    final dailyAvgSeconds = dateSet.isEmpty ? 0.0 : totalSeconds / dateSet.length;

    final sorted = dateSet.toList()..sort();
    int streak = 0, maxStreak = 0;
    DateTime? prev;
    for (final ms in sorted) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      if (prev != null && d.difference(prev).inDays == 1) {
        streak++;
      } else {
        streak = 1;
      }
      maxStreak = maxStreak > streak ? maxStreak : streak;
      prev = d;
    }

    return ReadingStats(
      totalSeconds: totalSeconds,
      totalTexts: totalTexts,
      dailyAvgSeconds: dailyAvgSeconds,
      longestStreak: maxStreak,
    );
  }
}
