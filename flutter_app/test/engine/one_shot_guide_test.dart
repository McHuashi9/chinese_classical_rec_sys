import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/one_shot_guide.dart';

/// 内存版 seen 存储：直接控制读写与时序，无需 `SharedPreferences.setMockInitialValues`。
class _FakeStore implements OneShotGuideStore {
  _FakeStore({this.seen = false});

  bool seen;
  int reads = 0;
  final List<String> written = [];

  /// 非空时 [isSeen] 挂起在该 Completer 上，用于验证 await 时序。
  Completer<bool>? pendingRead;

  @override
  Future<bool> isSeen(String key) {
    reads++;
    final pending = pendingRead;
    if (pending != null) return pending.future;
    return Future.value(seen);
  }

  @override
  Future<void> markSeen(String key) async {
    written.add(key);
    seen = true;
  }
}

void main() {
  group('OneShotGuide', () {
    test('seen key 值稳定（持久化契约）', () {
      expect(kInitQuizGuideSeenKey, 'init_quiz_guide_seen');
      expect(kInitTutorialSeenKey, 'init_tutorial_seen');
    });

    test('页面用的工厂构造把 key 内聚在 engine', () {
      expect(OneShotGuide.initQuiz(store: _FakeStore()).seenKey,
          kInitQuizGuideSeenKey);
      expect(OneShotGuide.initTutorial(store: _FakeStore()).seenKey,
          kInitTutorialSeenKey);
    });

    testWidgets('未看过：读 key 后插入浮层', (tester) async {
      final store = _FakeStore();
      final guide = OneShotGuide(seenKey: kInitQuizGuideSeenKey, store: store);
      late BuildContext ctx;
      await tester.pumpWidget(_host((c) => ctx = c));

      final shown =
          await guide.maybeShow(ctx, builder: (_) => const Text('guide'));
      await tester.pump();

      expect(shown, isTrue);
      expect(store.reads, 1);
      expect(guide.isShowing, isTrue);
      expect(find.text('guide'), findsOneWidget);
    });

    testWidgets('已看过：不插入浮层', (tester) async {
      final store = _FakeStore(seen: true);
      final guide = OneShotGuide(seenKey: kInitTutorialSeenKey, store: store);
      late BuildContext ctx;
      await tester.pumpWidget(_host((c) => ctx = c));

      final shown =
          await guide.maybeShow(ctx, builder: (_) => const Text('guide'));
      await tester.pump();

      expect(shown, isFalse);
      expect(store.reads, 1);
      expect(guide.isShowing, isFalse);
      expect(find.text('guide'), findsNothing);
    });

    testWidgets('force：不读 seen 直接展示（第 5 步路径）', (tester) async {
      final store = _FakeStore(seen: true);
      final guide = OneShotGuide(seenKey: kInitQuizGuideSeenKey, store: store);
      late BuildContext ctx;
      await tester.pumpWidget(_host((c) => ctx = c));

      final shown = await guide.maybeShow(
        ctx,
        force: true,
        builder: (_) => const Text('guide'),
      );
      await tester.pump();

      expect(shown, isTrue);
      expect(store.reads, 0, reason: 'force 展示不应读 seen key');
      expect(find.text('guide'), findsOneWidget);
    });

    testWidgets('await 时序：seen 未返回前不插入，返回后插入', (tester) async {
      final store = _FakeStore()..pendingRead = Completer<bool>();
      final guide = OneShotGuide(seenKey: kInitTutorialSeenKey, store: store);
      late BuildContext ctx;
      await tester.pumpWidget(_host((c) => ctx = c));

      final future = guide.maybeShow(ctx, builder: (_) => const Text('guide'));
      await tester.pump();
      expect(guide.isShowing, isFalse, reason: '读 key 未完成前不应插入');
      expect(find.text('guide'), findsNothing);

      store.pendingRead!.complete(false);
      expect(await future, isTrue);
      await tester.pump();
      expect(find.text('guide'), findsOneWidget);
    });

    testWidgets('await 时序：读取期间页面销毁则不插入', (tester) async {
      final store = _FakeStore()..pendingRead = Completer<bool>();
      final guide = OneShotGuide(seenKey: kInitTutorialSeenKey, store: store);
      late BuildContext pageCtx;
      await tester.pumpWidget(_host((c) => pageCtx = c));

      final future =
          guide.maybeShow(pageCtx, builder: (_) => const Text('guide'));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      store.pendingRead!.complete(false);
      expect(await future, isFalse);
      await tester.pump();
      expect(guide.isShowing, isFalse);
      expect(find.text('guide'), findsNothing);
    });

    testWidgets('finish：写 seen 并移除浮层', (tester) async {
      final store = _FakeStore();
      final guide = OneShotGuide(seenKey: kInitQuizGuideSeenKey, store: store);
      late BuildContext ctx;
      await tester.pumpWidget(_host((c) => ctx = c));

      await guide.maybeShow(ctx, builder: (_) => const Text('guide'));
      await tester.pump();
      await guide.finish();
      await tester.pump();

      expect(store.written, [kInitQuizGuideSeenKey]);
      expect(guide.isShowing, isFalse);
      expect(find.text('guide'), findsNothing);
    });

    testWidgets('dismiss：只移除浮层，不写 seen', (tester) async {
      final store = _FakeStore();
      final guide = OneShotGuide(seenKey: kInitQuizGuideSeenKey, store: store);
      late BuildContext ctx;
      await tester.pumpWidget(_host((c) => ctx = c));

      await guide.maybeShow(ctx, builder: (_) => const Text('guide'));
      await tester.pump();
      guide.dismiss();
      await tester.pump();

      expect(store.written, isEmpty);
      expect(guide.isShowing, isFalse);
      expect(find.text('guide'), findsNothing);
    });

    testWidgets('已展示时再次 maybeShow 幂等，不重复读 key', (tester) async {
      final store = _FakeStore();
      final guide = OneShotGuide(seenKey: kInitQuizGuideSeenKey, store: store);
      late BuildContext ctx;
      await tester.pumpWidget(_host((c) => ctx = c));

      await guide.maybeShow(ctx, builder: (_) => const Text('guide'));
      await tester.pump();
      expect(await guide.maybeShow(ctx, builder: (_) => const Text('other')),
          isTrue);
      await tester.pump();

      expect(store.reads, 1);
      expect(find.text('guide'), findsOneWidget);
      expect(find.text('other'), findsNothing);
    });
  });
}

/// 提供可用的 Overlay（MaterialApp 的 Navigator）并暴露一个后代 BuildContext。
Widget _host(void Function(BuildContext) onBuild) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        onBuild(context);
        return const Scaffold(body: SizedBox.expand());
      },
    ),
  );
}
