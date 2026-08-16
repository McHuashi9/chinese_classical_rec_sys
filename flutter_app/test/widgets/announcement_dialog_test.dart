import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/announcement.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/announcement_dialog.dart';

void main() {
  testWidgets('公告弹窗渲染作者的话/版本改动/知道了', (tester) async {
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
              ),
              child: const Text('打开公告'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('打开公告'));
    await tester.pumpAndSettle();

    expect(find.text('作者的话'), findsOneWidget);
    expect(find.text('版本改动'), findsOneWidget);
    expect(find.textContaining('感谢使用文言文推荐系统'), findsOneWidget);
    expect(find.textContaining('内容库与用户库分离'), findsOneWidget);
    expect(find.text('知道了'), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('作者的话'), findsNothing);
  });
}
