import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/widgets/annotation_popup.dart';

void main() {
  Widget wrap(AnnotationPopup popup) {
    return MaterialApp(
      home: Scaffold(body: popup),
    );
  }

  AnnotationPopup popup({
    int number = 3,
    String text = '岳阳楼：洞庭湖边的名楼',
    VoidCallback? onDismiss,
    Offset marker = const Offset(200, 200),
  }) {
    return AnnotationPopup(
      number: number,
      text: text,
      onDismiss: onDismiss ?? () {},
      fontScale: 1.0,
      markerCenterGlobal: marker,
    );
  }

  testWidgets('单条带词头：渲染词头、编号与内容', (tester) async {
    await tester.pumpWidget(wrap(popup(text: '岳阳楼：洞庭湖边的名楼')));
    expect(find.text('岳阳楼'), findsOneWidget);
    expect(find.text('〔3〕'), findsOneWidget);
    expect(find.text('洞庭湖边的名楼'), findsOneWidget);
  });

  testWidgets('无词头文本：标题降级为"注释 [n]"', (tester) async {
    await tester.pumpWidget(wrap(popup(text: '这是一段没有词头的注文')));
    expect(find.text('注释 [3]'), findsOneWidget);
    expect(find.text('这是一段没有词头的注文'), findsOneWidget);
  });

  testWidgets('多条注释：逐条渲染词头与内容', (tester) async {
    await tester.pumpWidget(wrap(popup(text: '词一：内容一\u3000词二：内容二')));
    expect(find.text('词一'), findsOneWidget);
    expect(find.text('内容一'), findsOneWidget);
    expect(find.text('词二'), findsOneWidget);
    expect(find.text('内容二'), findsOneWidget);
  });

  testWidgets('点关闭按钮触发 onDismiss', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(wrap(popup(onDismiss: () => dismissed++)));
    await tester.tap(find.byIcon(Icons.close));
    expect(dismissed, 1);
  });

  testWidgets('点遮罩区域触发 onDismiss', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(wrap(popup(onDismiss: () => dismissed++)));
    // 弹窗居中附近，点左上角遮罩
    await tester.tapAt(const Offset(3, 3));
    expect(dismissed, 1);
  });

  testWidgets('show() 插入 OverlayEntry，可移除并回调 onDismissed', (tester) async {
    var dismissed = 0;
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.shrink();
      }),
    ));
    AnnotationPopup.show(
      ctx,
      5,
      '词：义',
      onDismissed: () => dismissed++,
      fontScale: 1.0,
      markerCenterGlobal: const Offset(100, 100),
    );
    await tester.pump();
    expect(find.byType(AnnotationPopup), findsOneWidget);
    expect(find.text('词'), findsOneWidget);

    // 点遮罩 → entry.remove() + onDismissed
    await tester.tapAt(const Offset(3, 3));
    await tester.pump();
    expect(find.byType(AnnotationPopup), findsNothing);
    expect(dismissed, 1);
  });
}
