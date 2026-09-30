import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/widgets/spotlight_overlay.dart';

/// SpotlightOverlay 提炼自两个引导浮层，这里锁定其几何与外观不变量：
/// 屏幕 400×800（dpr 1）、默认 targetPadding 8、_edgeGap 16、卡片内边距 16。
const Size _screen = Size(400, 800);
const Key _bubbleKey = Key('bubble');

Future<void> _pump(WidgetTester tester, Widget overlay) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Stack(children: [overlay]))),
  );
}

void main() {
  testWidgets('无高亮目标：气泡贴安全区顶部（edgeGap + 卡片内边距）', (tester) async {
    await _pump(
      tester,
      const SpotlightOverlay(
        targetRect: null,
        bubbleEstimatedHeight: 100,
        child: SizedBox(key: _bubbleKey, width: 50, height: 30),
      ),
    );

    expect(tester.getRect(find.byKey(_bubbleKey)).top, 16 + 16);
  });

  testWidgets('高亮目标靠上：气泡放在目标下方（洞下沿 + edgeGap）', (tester) async {
    await _pump(
      tester,
      const SpotlightOverlay(
        targetRect: Rect.fromLTWH(100, 100, 50, 50),
        bubbleEstimatedHeight: 100,
        child: SizedBox(key: _bubbleKey, width: 50, height: 30),
      ),
    );

    // 洞 = target.inflate(8)，下沿 158；气泡顶 158+16=174，内容顶再 +16。
    expect(tester.getRect(find.byKey(_bubbleKey)).top, 174 + 16);
  });

  testWidgets('下方放不下：气泡翻到高亮目标上方', (tester) async {
    await _pump(
      tester,
      const SpotlightOverlay(
        targetRect: Rect.fromLTWH(100, 700, 50, 50),
        bubbleEstimatedHeight: 100,
        child: SizedBox(key: _bubbleKey, width: 50, height: 30),
      ),
    );

    // 洞上沿 692；气泡底 = 800 - 692 + 16 = 124 → 卡片底 676，内容底再 -16。
    expect(tester.getRect(find.byKey(_bubbleKey)).bottom, 676 - 16);
  });

  testWidgets('targetPadding 参与挖洞与外扩定位', (tester) async {
    await _pump(
      tester,
      const SpotlightOverlay(
        targetRect: Rect.fromLTWH(100, 100, 50, 50),
        targetPadding: 20,
        bubbleEstimatedHeight: 100,
        child: SizedBox(key: _bubbleKey, width: 50, height: 30),
      ),
    );

    // 洞下沿 = 150 + 20 = 170；气泡顶 170+16=186，内容顶再 +16。
    expect(tester.getRect(find.byKey(_bubbleKey)).top, 202);
  });

  testWidgets('输入屏障只挡高亮区之外，高亮目标仍可点击', (tester) async {
    var insideTaps = 0;
    var outsideTaps = 0;

    await _pump(
      tester,
      Stack(
        children: [
          Positioned(
            left: 110,
            top: 110,
            width: 40,
            height: 20,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => insideTaps++,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 110,
            top: 300,
            width: 40,
            height: 20,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => outsideTaps++,
              child: const SizedBox.expand(),
            ),
          ),
          const SpotlightOverlay(
            targetRect: Rect.fromLTWH(100, 100, 80, 40),
            bubbleEstimatedHeight: 50,
            child: SizedBox(key: _bubbleKey, width: 10, height: 10),
          ),
        ],
      ),
    );

    // 高亮区内（洞 = 92,92,96,56）不设屏障，点击落到下层控件。
    await tester.tapAt(const Offset(130, 120));
    await tester.pump();
    expect(insideTaps, 1);

    // 高亮区外被屏障吞掉，下层控件收不到。
    await tester.tapAt(const Offset(130, 310));
    await tester.pump();
    expect(outsideTaps, 0);
  });

  testWidgets('气泡卡片外观：elevation 6 / 圆角 12 / 内边距 16', (tester) async {
    await _pump(
      tester,
      const SpotlightOverlay(
        targetRect: null,
        bubbleEstimatedHeight: 100,
        child: SizedBox(key: _bubbleKey, width: 50, height: 30),
      ),
    );

    final cards = tester.widgetList<Material>(find.byType(Material));
    expect(
      cards.any((m) =>
          m.elevation == 6 && m.borderRadius == BorderRadius.circular(12)),
      isTrue,
      reason: '气泡卡片应保持 elevation 6 / 圆角 12',
    );
    final paddings = tester.widgetList<Padding>(find.byType(Padding));
    expect(
      paddings.any((p) => p.padding == const EdgeInsets.all(16)),
      isTrue,
      reason: '气泡卡片应保持 16 内边距',
    );
  });
}
