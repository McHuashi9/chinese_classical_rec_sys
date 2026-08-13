import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/empty_state.dart';

Widget wrap(Widget child, {bool dark = false}) => MaterialApp(
      theme: AppTheme.lightTheme(ScreenSize.medium, 1.0,
          accentColor: AppTheme.vermilion),
      darkTheme: AppTheme.darkTheme(ScreenSize.medium, 1.0,
          accentColor: AppTheme.vermilion),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('渲染标题与副文案', (tester) async {
    await tester.pumpWidget(wrap(const EmptyState(
      title: '未找到匹配篇目',
      subtitle: '换个关键词试试',
    )));
    expect(find.text('未找到匹配篇目'), findsOneWidget);
    expect(find.text('换个关键词试试'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('无副文案时不渲染副文案，可带动作按钮', (tester) async {
    await tester.pumpWidget(wrap(EmptyState(
      title: '暂无到期错题',
      action: OutlinedButton(
        onPressed: () {},
        child: const Text('返回'),
      ),
    )));
    expect(find.text('暂无到期错题'), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);
  });

  testWidgets('暗色模式正常渲染', (tester) async {
    await tester.pumpWidget(wrap(
      const EmptyState(title: '能力变化时将自动生成推荐'),
      dark: true,
    ));
    expect(find.text('能力变化时将自动生成推荐'), findsOneWidget);
  });
}
