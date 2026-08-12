import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/widgets/dialogs.dart';

void main() {
  group('showConfirmDialog', () {
    Future<bool?> Function() openDialog(
      WidgetTester tester, {
      String confirmLabel = '确定',
      String cancelLabel = '取消',
    }) {
      bool? result;
      return () async {
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showConfirmDialog(
                    ctx,
                    title: '对话框标题',
                    content: '对话框内容',
                    confirmLabel: confirmLabel,
                    cancelLabel: cancelLabel,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        return result;
      };
    }

    testWidgets('显示标题与内容', (tester) async {
      final open = openDialog(tester);
      await open();
      expect(find.text('对话框标题'), findsOneWidget);
      expect(find.text('对话框内容'), findsOneWidget);
    });

    testWidgets('点"确定"返回 true', (tester) async {
      final open = openDialog(tester);
      await open();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('点"取消"返回 false', (tester) async {
      final open = openDialog(tester);
      await open();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('barrierDismissible=false：点遮罩不关闭', (tester) async {
      final open = openDialog(tester);
      await open();
      // 点对话框外（屏幕左上角）触发 barrier 点击
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('自定义按钮文案', (tester) async {
      final open = openDialog(
        tester,
        confirmLabel: '同意',
        cancelLabel: '再想想',
      );
      await open();
      expect(find.text('同意'), findsOneWidget);
      expect(find.text('再想想'), findsOneWidget);
    });
  });
}
