import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/models/reading_view_data.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/widgets/reading_frame.dart';

void main() {
  Widget wrap(ReadingViewData data, SettingsController settings) {
    return MaterialApp(
      home: ChangeNotifierProvider<SettingsController>.value(
        value: settings,
        child: Scaffold(body: ReadingFrame(viewData: data)),
      ),
    );
  }

  ReadingViewData buildViewData({
    required bool showTranslation,
    required VoidCallback onToggle,
    required void Function(int, int) onPaginate,
    int charCount = 0,
    int elapsedSeconds = 0,
    VoidCallback? onComplete,
  }) {
    return ReadingViewData(
      text: ChineseText(
        id: 1, title: '测试', author: 'a', dynasty: '唐',
        content: '原文内容\n\n第二段原文内容',
        charCount: charCount,
      ),
      pages: const ['第一页原文内容', '第二页原文内容'],
      currentPage: 0,
      totalPages: 2,
      formattedTime: '00:00',
      isDark: false,
      elapsedSeconds: elapsedSeconds,
      alreadyTracked: false,
      annotations: const {},
      showTranslation: showTranslation,
      onToggleTranslation: onToggle,
      onPaginate: onPaginate,
      onNextPage: () {},
      onPrevPage: () {},
      onComplete: onComplete ?? () {},
      onAbandon: () {},
      onExit: () {},
    );
  }

  testWidgets('切换 showTranslation 后触发重新分页（pages 非空也要分页）',
      (tester) async {
    final settings = SettingsController();
    var showTranslation = false;
    var paginateCount = 0;

    Widget rebuild() => wrap(
          buildViewData(
            showTranslation: showTranslation,
            onToggle: () => showTranslation = !showTranslation,
            onPaginate: (w, h) => paginateCount++,
          ),
          settings,
        );

    await tester.pumpWidget(rebuild());
    await tester.pump();
    final before = paginateCount;

    showTranslation = true;
    await tester.pumpWidget(rebuild());
    await tester.pump();
    expect(paginateCount, greaterThan(before));
  });

  testWidgets('未切换时 viewData 重建不重复分页', (tester) async {
    final settings = SettingsController();
    var paginateCount = 0;

    final data = buildViewData(
      showTranslation: false,
      onToggle: () {},
      onPaginate: (w, h) => paginateCount++,
    );

    await tester.pumpWidget(wrap(data, settings));
    await tester.pump();
    final afterFirst = paginateCount;
    expect(afterFirst, greaterThan(0));

    await tester.pumpWidget(wrap(
      buildViewData(
        showTranslation: false,
        onToggle: () {},
        onPaginate: (w, h) => paginateCount++,
      ),
      settings,
    ));
    await tester.pump();
    expect(paginateCount, afterFirst);
  });

  testWidgets('fontScale 变化触发重新分页', (tester) async {
    final settings = SettingsController();
    var paginateCount = 0;

    await tester.pumpWidget(wrap(
      buildViewData(
        showTranslation: false,
        onToggle: () {},
        onPaginate: (w, h) => paginateCount++,
      ),
      settings,
    ));
    await tester.pump();
    final before = paginateCount;

    settings.setFontScale(1.25);
    await tester.pump();
    expect(paginateCount, greaterThan(before));
  });

  testWidgets('短文完成按钮按动态阈值启用和倒计时', (tester) async {
    final settings = SettingsController();
    // charCount=50 -> T_min = 50 / 150 * 60 = 20s
    var completed = false;

    await tester.pumpWidget(wrap(
      buildViewData(
        showTranslation: false,
        onToggle: () {},
        onPaginate: (w, h) {},
        charCount: 50,
        elapsedSeconds: 19,
        onComplete: () => completed = true,
      ),
      settings,
    ));
    await tester.pump();

    expect(find.text('1s'), findsOneWidget);
    expect(find.text('完成'), findsNothing);

    await tester.pumpWidget(wrap(
      buildViewData(
        showTranslation: false,
        onToggle: () {},
        onPaginate: (w, h) {},
        charCount: 50,
        elapsedSeconds: 20,
        onComplete: () => completed = true,
      ),
      settings,
    ));
    await tester.pump();

    expect(find.text('完成'), findsOneWidget);
    await tester.tap(find.text('完成'));
    expect(completed, isTrue);
  });

  testWidgets('长文完成按钮在 30s 时仍按动态阈值禁用', (tester) async {
    final settings = SettingsController();
    // charCount=1000 -> T_min = 1000 / 150 * 60 = 400s
    var completed = false;

    await tester.pumpWidget(wrap(
      buildViewData(
        showTranslation: false,
        onToggle: () {},
        onPaginate: (w, h) {},
        charCount: 1000,
        elapsedSeconds: 30,
        onComplete: () => completed = true,
      ),
      settings,
    ));
    await tester.pump();

    expect(find.text('370s'), findsOneWidget);
    expect(find.text('完成'), findsNothing);

    await tester.tap(find.text('370s'));
    expect(completed, isFalse);
  });
}
