import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/feedback_mailto.dart';
import 'package:chinese_classical_rec_sys/engine/feedback_submit.dart';
import 'package:chinese_classical_rec_sys/widgets/feedback_dialog.dart';

Future<void> _openDialog(
  WidgetTester tester, {
  Future<String> Function()? loader,
  Future<bool> Function(Uri uri)? launcher,
  Future<FeedbackSubmitResult> Function(FeedbackDraft draft)? submitFeedback,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showFeedbackDialog(
              context,
              appVersion: '1.0.2',
              platform: 'Linux',
              contentDataVersion: 'data-20260816-213645',
              schemaVersions: '用户 1 · 内容 1',
              diagnosticsLoader:
                  loader ?? () async => '【环境信息】\nApp 版本：1.0.2',
              logTailLoader: () async => 'line1',
              mailtoLauncher: launcher ?? (_) async => true,
              submitFeedback: submitFeedback,
            ),
            child: const Text('打开反馈'),
          ),
        ),
      ),
    ),
  ));

  await tester.tap(find.text('打开反馈'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('反馈弹窗展示表单与操作按钮', (tester) async {
    await _openDialog(tester);

    expect(find.text('反馈 Bug / 意见'), findsOneWidget);
    expect(find.text('类型'), findsOneWidget);
    expect(find.text('标题 *'), findsOneWidget);
    expect(find.text('描述 *'), findsOneWidget);
    expect(find.text('在线提交到开发者（方便）'), findsOneWidget);
    expect(find.text('打开默认邮件客户端'), findsOneWidget);
    expect(find.text('复制完整反馈内容'), findsOneWidget);
    expect(find.text('复制诊断信息'), findsOneWidget);
    expect(find.text('复制邮箱地址'), findsOneWidget);
  });

  testWidgets('标题和描述为空时校验拦截', (tester) async {
    await _openDialog(tester);

    await tester.tap(find.text('打开默认邮件客户端'));
    await tester.pumpAndSettle();

    expect(find.text('请填写标题'), findsOneWidget);
    expect(find.text('请填写描述'), findsOneWidget);
  });

  testWidgets('复制完整反馈内容写入剪贴板', (tester) async {
    final log = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        log.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await _openDialog(tester);

    await tester.enterText(find.byType(TextFormField).at(0), '初始化后无法进入阅读');
    await tester.enterText(find.byType(TextFormField).at(1), '点击文章后一直转圈');
    await tester.tap(find.text('复制完整反馈内容'));
    await tester.pumpAndSettle();

    expect(
      log.where((c) => c.method == 'Clipboard.setData'),
      hasLength(1),
    );
    final arguments = log
        .firstWhere((c) => c.method == 'Clipboard.setData')
        .arguments as Map;
    expect(arguments['text'], contains('收件人：mc_huashi9@163.com'));
    expect(arguments['text'], contains('主题：【Bug反馈】初始化后无法进入阅读'));
    expect(arguments['text'], contains('点击文章后一直转圈'));
  });

  testWidgets('复制诊断信息写入剪贴板', (tester) async {
    final log = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        log.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await _openDialog(
      tester,
      loader: () async => '【环境信息】\nApp 版本：1.0.2',
    );

    await tester.ensureVisible(find.text('复制诊断信息'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制诊断信息'));
    await tester.pumpAndSettle();

    final arguments = log
        .firstWhere((c) => c.method == 'Clipboard.setData')
        .arguments as Map;
    expect(arguments['text'], contains('【环境信息】'));
  });

  testWidgets('打开邮件客户端调用注入的 launcher', (tester) async {
    Uri? launched;
    await _openDialog(
      tester,
      launcher: (uri) async {
        launched = uri;
        return true;
      },
    );

    await tester.enterText(find.byType(TextFormField).at(0), '标题');
    await tester.enterText(find.byType(TextFormField).at(1), '描述');
    await tester.ensureVisible(find.text('打开默认邮件客户端'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开默认邮件客户端'));
    await tester.pumpAndSettle();

    expect(launched, isNotNull);
    expect(launched!.toString(), startsWith('mailto:mc_huashi9@163.com?subject='));
  });

  testWidgets('打开邮件客户端失败时提示复制兜底', (tester) async {
    await _openDialog(
      tester,
      launcher: (_) async => false,
    );

    await tester.enterText(find.byType(TextFormField).at(0), '标题');
    await tester.enterText(find.byType(TextFormField).at(1), '描述');
    await tester.ensureVisible(find.text('打开默认邮件客户端'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开默认邮件客户端'));
    await tester.pumpAndSettle();

    expect(find.textContaining('未找到可用的邮件客户端'), findsOneWidget);
  });

  testWidgets('在线提交按钮当前禁用', (tester) async {
    await _openDialog(tester);

    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('在线提交到开发者（方便）'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });
}
