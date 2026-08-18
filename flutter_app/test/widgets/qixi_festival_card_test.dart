import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/qixi_festival_card.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme(ScreenSize.medium, 1.0,
        accentColor: AppTheme.vermilion),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('非七夕不显示卡片', (tester) async {
    await tester.pumpWidget(
      _wrap(QixiFestivalCard(now: DateTime(2024, 8, 9))),
    );
    await tester.pumpAndSettle();

    expect(find.text('七夕快乐'), findsNothing);
  });

  testWidgets('七夕显示卡片且可展开诗词', (tester) async {
    await tester.pumpWidget(
      _wrap(QixiFestivalCard(now: DateTime(2024, 8, 10))),
    );
    await tester.pumpAndSettle();

    expect(find.text('七夕快乐'), findsOneWidget);
    expect(find.textContaining('金风玉露一相逢'), findsNothing);

    await tester.tap(find.text('七夕快乐'));
    await tester.pumpAndSettle();

    expect(find.textContaining('金风玉露一相逢'), findsOneWidget);
    expect(find.textContaining('两情若是久长时'), findsOneWidget);
  });
}
