import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/announcement.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/announcement_dialog.dart';

Future<void> _openDialog(
  WidgetTester tester, {
  AnnouncementMode initialMode = AnnouncementMode.always,
  ValueChanged<AnnouncementMode>? onModeChanged,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme(ScreenSize.medium, 1.0,
        accentColor: AppTheme.vermilion),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => AnnouncementDialog.show(
              context,
              announcement: kCurrentAnnouncement,
              initialMode: initialMode,
              onModeChanged: onModeChanged,
            ),
            child: const Text('打开公告'),
          ),
        ),
      ),
    ),
  ));

  await tester.tap(find.text('打开公告'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('公告弹窗渲染 v1.1.1 文案与弹出模式选项', (tester) async {
    await _openDialog(tester);

    expect(find.text('作者的话'), findsOneWidget);
    expect(find.text('版本改动'), findsOneWidget);
    expect(find.textContaining('感谢使用文言文推荐系统'), findsOneWidget);
    expect(find.textContaining('学习数据导出'), findsOneWidget);
    expect(find.text('以后只在更新后弹出'), findsOneWidget);
    final checkbox = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(checkbox.value, isFalse);
    expect(find.text('知道了'), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('作者的话'), findsNothing);
  });

  testWidgets('勾选后只在更新后弹出会回调 onUpdate', (tester) async {
    AnnouncementMode? changed;
    await _openDialog(tester, onModeChanged: (m) => changed = m);

    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    final checkbox = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(checkbox.value, isTrue);
    expect(changed, AnnouncementMode.onUpdate);
  });

  testWidgets('initialMode 为 onUpdate 时复选框默认勾选', (tester) async {
    await _openDialog(tester, initialMode: AnnouncementMode.onUpdate);

    final checkbox = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(checkbox.value, isTrue);
  });
}
