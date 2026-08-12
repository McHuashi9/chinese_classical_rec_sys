import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/service/history_service.dart';
import 'package:chinese_classical_rec_sys/widgets/recent_reading_list.dart';

/// 以"今天"为基准构造记录：dayOffset 0=今天、1=昨天…
ReadingRecord rec(int textId, double minutes, int dayOffset) {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: dayOffset));
  return ReadingRecord(
    textId: textId,
    title: '文章$textId',
    author: '作者$textId',
    dynasty: '唐',
    readTime: minutes * 60,
    timestamp: day.millisecondsSinceEpoch ~/ 1000,
  );
}

void main() {
  Widget wrap(List<ReadingRecord> records, {void Function(int)? onTap}) {
    return MaterialApp(
      home: Scaffold(
        // 与真实页面一致：列表放在可滚动容器中，避免 10 条溢出
        body: SingleChildScrollView(
          child: RecentReadingList(records: records, onTap: onTap),
        ),
      ),
    );
  }

  testWidgets('空列表渲染 SizedBox.shrink，无标题', (tester) async {
    await tester.pumpWidget(wrap(const []));
    expect(find.byType(SizedBox), findsOneWidget);
    expect(find.text('最近阅读'), findsNothing);
  });

  testWidgets('渲染标题、作者与阅读分钟', (tester) async {
    await tester.pumpWidget(wrap([rec(1, 30, 0)]));
    expect(find.text('最近阅读'), findsOneWidget);
    expect(find.text('文章1 · 作者1'), findsOneWidget);
    expect(find.text('30 分钟'), findsOneWidget);
  });

  testWidgets('超过 10 条只显示前 10 条', (tester) async {
    await tester.pumpWidget(
      wrap([for (var i = 1; i <= 11; i++) rec(i, 10, i)]),
    );
    expect(find.byType(ListTile), findsNWidgets(10));
    expect(find.text('文章11 · 作者11'), findsNothing);
  });

  testWidgets('日期：今天显示"今天"', (tester) async {
    await tester.pumpWidget(wrap([rec(1, 10, 0)]));
    expect(find.text('今天'), findsOneWidget);
  });

  testWidgets('日期：昨天显示"昨天"', (tester) async {
    await tester.pumpWidget(wrap([rec(1, 10, 1)]));
    expect(find.text('昨天'), findsOneWidget);
  });

  testWidgets('日期：2~7 天前显示星期', (tester) async {
    await tester.pumpWidget(wrap([rec(1, 10, 3)]));
    const days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final expected = days[
        DateTime.now().subtract(const Duration(days: 3)).weekday - 1];
    expect(find.text(expected), findsOneWidget);
  });

  testWidgets('日期：8 天前显示月/日', (tester) async {
    await tester.pumpWidget(wrap([rec(1, 10, 8)]));
    final d = DateTime.now().subtract(const Duration(days: 8));
    expect(find.text('${d.month}/${d.day}'), findsOneWidget);
  });

  testWidgets('点击条目触发 onTap 并携带 textId', (tester) async {
    int? tappedId;
    await tester.pumpWidget(
      wrap([rec(7, 10, 0)], onTap: (id) => tappedId = id),
    );
    await tester.tap(find.text('文章7 · 作者7'));
    expect(tappedId, 7);
  });

  testWidgets('onTap 为 null 时条目不可点击', (tester) async {
    await tester.pumpWidget(wrap([rec(1, 10, 0)]));
    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.onTap, isNull);
  });
}
