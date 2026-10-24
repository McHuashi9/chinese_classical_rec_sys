import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/dialogs.dart';

void main() {
  const accent = Color(0xFF3A6B8C);

  test('亮色弹窗主题使用暖卡片背景、1px 边框和 8px 圆角', () {
    final theme = AppTheme.lightTheme(
      ScreenSize.medium,
      1.0,
      accentColor: accent,
    );
    final dialogTheme = theme.dialogTheme;

    expect(dialogTheme.backgroundColor, AppTheme.cardBg);
    expect(dialogTheme.elevation, 0);
    expect(dialogTheme.surfaceTintColor, Colors.transparent);
    final shape = dialogTheme.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(8));
    expect(shape.side.color, AppTheme.border);
    expect(shape.side.width, 1);
  });

  test('暗色弹窗主题使用暗卡片背景与浅色边框', () {
    final theme = AppTheme.darkTheme(
      ScreenSize.medium,
      1.0,
      accentColor: accent,
    );
    final dialogTheme = theme.dialogTheme;

    expect(dialogTheme.backgroundColor, AppTheme.darkCard);
    final shape = dialogTheme.shape! as RoundedRectangleBorder;
    expect(shape.side.color, AppTheme.borderLight);
  });

  testWidgets('AlertDialog 实际渲染应用暖卡片背景', (tester) async {
    final theme = AppTheme.lightTheme(
      ScreenSize.medium,
      1.0,
      accentColor: accent,
    );
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showConfirmDialog(
                context,
                title: '确认',
                content: '内容',
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, AppTheme.cardBg);
  });
}
