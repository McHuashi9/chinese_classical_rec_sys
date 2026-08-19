import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chinese_classical_rec_sys/models/user_profile.dart';
import 'package:chinese_classical_rec_sys/widgets/profile_dialogs.dart';

void main() {
  group('shouldShowNewUserWelcome / markNewUserWelcomeSeen', () {
    const profile =
        UserProfile(id: 1, name: '默认用户', createdAt: 1001, lastUsedAt: 2001);

    test('无标记、单档案且未初始化时展示', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(shouldShowNewUserWelcome(prefs, const [profile], false), isTrue);
    });

    test('已有欢迎页标记时不展示', () async {
      SharedPreferences.setMockInitialValues({kNewUserWelcomeSeenKey: true});
      final prefs = await SharedPreferences.getInstance();
      expect(shouldShowNewUserWelcome(prefs, const [profile], false), isFalse);
    });

    test('已初始化时不展示', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(shouldShowNewUserWelcome(prefs, const [profile], true), isFalse);
    });

    test('多档案时不展示', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(
        shouldShowNewUserWelcome(prefs, const [
          profile,
          UserProfile(id: 2, name: '小明', createdAt: 1002, lastUsedAt: 2002),
        ], false),
        isFalse,
      );
    });

    test('markNewUserWelcomeSeen 写入标记', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await markNewUserWelcomeSeen(prefs);
      expect(prefs.getBool(kNewUserWelcomeSeenKey), isTrue);
    });

    test('markProfileOnboardingSeen 写入标记', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await markProfileOnboardingSeen(prefs);
      expect(prefs.getBool(kProfileOnboardedKey), isTrue);
    });
  });

  group('promptProfileName', () {
    Widget host({VoidCallback? onResult}) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  await promptProfileName(context, title: '命名');
                  onResult?.call();
                },
                child: const Text('开始'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('取消返回并关闭对话框', (tester) async {
      await tester.pumpWidget(host());
      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('命名'), findsNothing);
    });

    testWidgets('有效名称返回规范化结果', (tester) async {
      String? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await promptProfileName(context, title: '命名');
                },
                child: const Text('开始'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  小明  ');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(result, '小明');
    });

    testWidgets('空名提示并关闭对话框', (tester) async {
      await tester.pumpWidget(host());
      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('名称不能为空'), findsOneWidget);
      expect(find.text('命名'), findsNothing);
    });

    testWidgets('超长名提示并关闭对话框', (tester) async {
      await tester.pumpWidget(host());
      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '长' * 22);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('名称过长，请缩短'), findsOneWidget);
      expect(find.text('命名'), findsNothing);
    });
  });
}
