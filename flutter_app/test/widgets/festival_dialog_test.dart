import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/chinese_festivals.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/festival_dialog.dart';

void main() {
  testWidgets('节日弹窗展示标题与诗文，且没有“以后不再弹出”选项', (tester) async {
    const festival = Festival(
      id: 'qixi',
      lunarMonth: 7,
      lunarDay: 7,
      title: '七夕快乐',
      subtitle: '农历七月初七 · 鹊桥仙·纤云弄巧',
      content: '金风玉露一相逢',
    );
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme(ScreenSize.medium, 1.0,
          accentColor: AppTheme.vermilion),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => FestivalDialog.show(context, festival: festival),
              child: const Text('打开节日弹窗'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('打开节日弹窗'));
    await tester.pumpAndSettle();

    expect(find.text('七夕快乐'), findsOneWidget);
    expect(find.text('金风玉露一相逢'), findsOneWidget);
    expect(find.textContaining('以后只在更新后弹出'), findsNothing);
    expect(find.textContaining('以后不再弹出'), findsNothing);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('七夕快乐'), findsNothing);
  });
}
