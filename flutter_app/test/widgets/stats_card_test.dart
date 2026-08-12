import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/service/history_service.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/widgets/stats_card.dart';

void main() {
  Widget wrap(ReadingStats stats) {
    return MaterialApp(
      home: ChangeNotifierProvider<SettingsController>.value(
        value: SettingsController(),
        child: Scaffold(body: StatsCard(stats: stats)),
      ),
    );
  }

  const stats = ReadingStats(
    totalSeconds: 3661,
    totalTexts: 5,
    dailyAvgSeconds: 600.0,
    longestStreak: 3,
  );

  testWidgets('渲染四项统计：总时长/篇数/日均/连续', (tester) async {
    await tester.pumpWidget(wrap(stats));
    expect(find.text('总阅读时间'), findsOneWidget);
    expect(find.text('1h 1m'), findsOneWidget);
    expect(find.text('已读篇数'), findsOneWidget);
    expect(find.text('5 篇'), findsOneWidget);
    expect(find.text('日均阅读'), findsOneWidget);
    expect(find.text('10 分钟'), findsOneWidget);
    expect(find.text('最长连续'), findsOneWidget);
    expect(find.text('3 天'), findsOneWidget);
  });

  testWidgets('总时长不足 1 小时显示为 Nm', (tester) async {
    await tester.pumpWidget(wrap(const ReadingStats(
      totalSeconds: 59,
      totalTexts: 0,
      dailyAvgSeconds: 0,
      longestStreak: 0,
    )));
    expect(find.text('0m'), findsOneWidget);
  });

  testWidgets('总时长整小时显示 Nh 0m', (tester) async {
    await tester.pumpWidget(wrap(const ReadingStats(
      totalSeconds: 7200,
      totalTexts: 0,
      dailyAvgSeconds: 0,
      longestStreak: 0,
    )));
    expect(find.text('2h 0m'), findsOneWidget);
  });

  testWidgets('零数据也能渲染', (tester) async {
    await tester.pumpWidget(wrap(const ReadingStats(
      totalSeconds: 0,
      totalTexts: 0,
      dailyAvgSeconds: 0,
      longestStreak: 0,
    )));
    expect(find.text('0 篇'), findsOneWidget);
    expect(find.text('0 分钟'), findsOneWidget);
    expect(find.text('0 天'), findsOneWidget);
  });
}
