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
  }) {
    return ReadingViewData(
      text: const ChineseText(
        id: 1, title: '测试', author: 'a', dynasty: '唐',
        content: '原文内容\n\n第二段原文内容',
      ),
      pages: const ['第一页原文内容', '第二页原文内容'],
      currentPage: 0,
      totalPages: 2,
      formattedTime: '00:00',
      isDark: false,
      elapsedSeconds: 0,
      alreadyTracked: false,
      annotations: const {},
      showTranslation: showTranslation,
      onToggleTranslation: onToggle,
      onPaginate: onPaginate,
      onNextPage: () {},
      onPrevPage: () {},
      onComplete: () {},
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
}
