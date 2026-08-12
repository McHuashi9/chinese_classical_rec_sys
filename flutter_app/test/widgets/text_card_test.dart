import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/widgets/text_card.dart';

void main() {
  Widget wrap(TextCard card) =>
      MaterialApp(home: Scaffold(body: card));

  testWidgets('渲染标题与副标题', (tester) async {
    await tester.pumpWidget(wrap(TextCard(
      title: '岳阳楼记',
      subtitle: '范仲淹 · 宋',
      trailing: const Icon(Icons.chevron_right),
      onTap: () {},
    )));
    expect(find.text('岳阳楼记'), findsOneWidget);
    expect(find.text('范仲淹 · 宋'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('subtitle 为 null 时不渲染副标题', (tester) async {
    await tester.pumpWidget(wrap(TextCard(
      title: '岳阳楼记',
      trailing: const SizedBox.shrink(),
      onTap: () {},
    )));
    expect(find.text('岳阳楼记'), findsOneWidget);
  });

  testWidgets('subtitle 为空串时不渲染副标题', (tester) async {
    await tester.pumpWidget(wrap(TextCard(
      title: '岳阳楼记',
      subtitle: '',
      trailing: const SizedBox.shrink(),
      onTap: () {},
    )));
    expect(find.text('岳阳楼记'), findsOneWidget);
  });

  testWidgets('点击卡片触发 onTap', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(wrap(TextCard(
      title: '岳阳楼记',
      trailing: const SizedBox.shrink(),
      onTap: () => tapped++,
    )));
    await tester.tap(find.text('岳阳楼记'));
    expect(tapped, 1);
  });

  testWidgets('长标题省略号截断不抛错', (tester) async {
    final long = '文' * 300;
    await tester.pumpWidget(wrap(TextCard(
      title: long,
      subtitle: long,
      trailing: const SizedBox.shrink(),
      onTap: () {},
    )));
    expect(find.byType(TextCard), findsOneWidget);
  });
}
