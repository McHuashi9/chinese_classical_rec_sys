import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_classical_rec_sys/widgets/profile_avatar.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

void main() {
  testWidgets('ProfileAvatar 显示档案名首字', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ProfileAvatar(name: '小明', id: 1)),
      ),
    );

    expect(find.text('小'), findsOneWidget);
  });

  testWidgets('ProfileAvatar 颜色按 id 稳定分配', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              ProfileAvatar(name: '甲', id: 1),
              ProfileAvatar(name: '乙', id: 2),
              ProfileAvatar(name: '丙', id: 13),
            ],
          ),
        ),
      ),
    );

    final avatars =
        tester.widgetList<CircleAvatar>(find.byType(CircleAvatar)).toList();
    expect(avatars.length, 3);
    expect(avatars[0].backgroundColor,
        AppTheme.profileAvatarColors[1 % AppTheme.profileAvatarColors.length]);
    expect(avatars[1].backgroundColor,
        AppTheme.profileAvatarColors[2 % AppTheme.profileAvatarColors.length]);
    expect(avatars[2].backgroundColor,
        AppTheme.profileAvatarColors[13 % AppTheme.profileAvatarColors.length]);
  });

  testWidgets('ProfileAvatar 空名显示问号', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ProfileAvatar(name: '', id: 0)),
      ),
    );

    expect(find.text('?'), findsOneWidget);
  });
}
