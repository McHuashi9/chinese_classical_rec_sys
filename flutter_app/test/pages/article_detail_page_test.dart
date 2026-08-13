import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/pages/article_detail_page.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/radar_chart.dart';

/// 仅覆写页面用到的两个能力点；页面后续若调用未覆写方法
/// （如 history/_historyService!）会炸，需在此补覆写。
class _FakeCoordinator extends AppCoordinator {
  _FakeCoordinator({
    required super.navCtrl,
    required super.settingsCtrl,
    required super.readingCtrl,
    required super.userCtrl,
    required super.readTracker,
  });

  ChineseText? text;
  int loadCalls = 0;

  @override
  ChineseText? getTextDetail(int textId) => text;

  @override
  bool loadTextForReading(int textId) {
    loadCalls++;
    return true;
  }
}

ChineseText _text({
  String background = '本文为欧阳修名篇，写醉翁亭山水与宴饮之乐。',
  List<double>? difficulties,
}) {
  return ChineseText(
    id: 1,
    title: '醉翁亭记',
    author: '欧阳修',
    dynasty: '宋',
    source: '古文观止',
    background: background,
    content: '环滁皆山也。其西南诸峰，林壑尤美。',
    charCount: 1520,
    difficulties: difficulties ?? List.filled(10, 0.5),
  );
}

void main() {
  late NavigationController navCtrl;
  late SettingsController settingsCtrl;
  late ReadTracker readTracker;
  late ReadingController readingCtrl;
  late UserController userCtrl;
  late _FakeCoordinator coord;

  setUp(() {
    navCtrl = NavigationController();
    settingsCtrl = SettingsController();
    readTracker = ReadTracker();
    readingCtrl = ReadingController(readTracker);
    userCtrl = UserController();
    coord = _FakeCoordinator(
      navCtrl: navCtrl,
      settingsCtrl: settingsCtrl,
      readingCtrl: readingCtrl,
      userCtrl: userCtrl,
      readTracker: readTracker,
    );
  });

  tearDown(() {
    readingCtrl.dispose();
    userCtrl.dispose();
  });

  Widget wrap(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: navCtrl),
        ChangeNotifierProvider.value(value: settingsCtrl),
        ChangeNotifierProvider.value(value: readingCtrl),
        ChangeNotifierProvider<UserController>.value(value: userCtrl),
        Provider<AppCoordinator>.value(value: coord),
      ],
      child: MaterialApp(home: child),
    );
  }

  testWidgets('完整渲染：标题/作者朝代/来源/预计阅读/背景/开始阅读', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    coord.text = _text();
    final user = User.allocate(calloc);
    for (var i = 0; i < 10; i++) {
      user.setAbility(i, 0.3);
    }
    userCtrl.setUser(user);
    await tester.pumpWidget(wrap(const ArticleDetailPage(textId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('醉翁亭记'), findsOneWidget);
    expect(find.text('欧阳修 · 宋'), findsOneWidget);
    expect(find.text('古文观止'), findsOneWidget);
    expect(find.text('预计阅读 10.1 分钟 · 共 1520 字'), findsOneWidget);
    expect(find.text('背景介绍'), findsOneWidget);
    expect(find.text('本文为欧阳修名篇，写醉翁亭山水与宴饮之乐。'), findsOneWidget);
    expect(find.text('开始阅读'), findsOneWidget);
  });

  testWidgets('user 非空：渲染难度匹配雷达与预计收益（公式期望值）', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    // 难度 0.5、能力 0.5 → x = 0.5-0.5-0.13 = -0.13
    // gain = exp(-0.13²/(2·0.25²)) = exp(-0.1352) ≈ 0.87354 → 87.4%
    coord.text = _text();
    final user = User.allocate(calloc);
    for (var i = 0; i < 10; i++) {
      user.setAbility(i, 0.5);
    }
    userCtrl.setUser(user);
    await tester.pumpWidget(wrap(const ArticleDetailPage(textId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('难度匹配'), findsOneWidget);
    expect(find.byType(RadarChart), findsOneWidget);
    expect(find.text('预计阅读收益'), findsOneWidget);
    expect(find.text('综合收益 '), findsOneWidget);
    expect(find.text('87.4%'), findsOneWidget);
    expect(find.text('  ·  10 维平均'), findsOneWidget);
    expect(find.text('平均句长'), findsOneWidget);
    expect(find.text('语义复杂度'), findsOneWidget);
    expect(find.text('87%'), findsNWidgets(10));
  });

  testWidgets('能力 0.3、难度 0.5 → 综合收益 96.2%', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    coord.text = _text();
    final user = User.allocate(calloc);
    for (var i = 0; i < 10; i++) {
      user.setAbility(i, 0.3);
    }
    userCtrl.setUser(user);
    await tester.pumpWidget(wrap(const ArticleDetailPage(textId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('96.2%'), findsOneWidget);
    expect(find.text('96%'), findsNWidgets(10));
  });

  testWidgets('user 为 null：不出难度匹配与收益区，仍可开始阅读', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    coord.text = _text();
    await tester.pumpWidget(wrap(const ArticleDetailPage(textId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('难度匹配'), findsNothing);
    expect(find.text('预计阅读收益'), findsNothing);
    expect(find.byType(RadarChart), findsNothing);
    expect(find.text('开始阅读'), findsOneWidget);
  });

  testWidgets('难度维数不足 10：不出匹配与收益区', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    coord.text = _text(difficulties: const [0.5, 0.5, 0.5]);
    final user = User.allocate(calloc);
    userCtrl.setUser(user);
    await tester.pumpWidget(wrap(const ArticleDetailPage(textId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('难度匹配'), findsNothing);
    expect(find.text('预计阅读收益'), findsNothing);
  });

  testWidgets('text 未找到：显示文章未找到', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    coord.text = null;
    await tester.pumpWidget(wrap(const ArticleDetailPage(textId: 404)));
    await tester.pumpAndSettle();

    expect(find.text('文章未找到'), findsOneWidget);
    expect(find.text('无法加载文章信息'), findsOneWidget);
    expect(find.text('开始阅读'), findsNothing);
  });

  testWidgets('朝代为空：只显示作者', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    coord.text = ChineseText(
      id: 1,
      title: '醉翁亭记',
      author: '欧阳修',
      dynasty: '',
      source: '古文观止',
      difficulties: List.filled(10, 0.5),
    );
    await tester.pumpWidget(wrap(const ArticleDetailPage(textId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('欧阳修'), findsOneWidget);
    expect(find.text('欧阳修 · 宋'), findsNothing);
  });

  testWidgets('背景以【特征待定】开头：渲染特征待定徽标', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    coord.text = _text(background: '【特征待定】该篇特征数据缺失，难度暂按中档估算。');
    await tester.pumpWidget(wrap(const ArticleDetailPage(textId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('特征待定'), findsOneWidget);
  });

  testWidgets('特征待定徽标：暗色模式分支', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    settingsCtrl.setDarkMode(true);
    coord.text = _text(background: '【特征待定】该篇特征数据缺失，难度暂按中档估算。');
    await tester.pumpWidget(wrap(const ArticleDetailPage(textId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('特征待定'), findsOneWidget);
    // 暗色分支：徽标须用 darkVermilion 底色/描边（与亮色的 vermilion 不同）
    final chip = tester.widget<Chip>(find.ancestor(
      of: find.text('特征待定'),
      matching: find.byType(Chip),
    ));
    expect(chip.backgroundColor, AppTheme.darkVermilion.withAlpha(40));
    expect(chip.side!.color, AppTheme.darkVermilion);
    expect(chip.labelStyle!.color, AppTheme.darkVermilion);
  });

  testWidgets('来源为空：不渲染来源与特征徽标区', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    coord.text = ChineseText(
      id: 1,
      title: '醉翁亭记',
      author: '欧阳修',
      dynasty: '宋',
      background: '',
      difficulties: List.filled(10, 0.5),
    );
    await tester.pumpWidget(wrap(const ArticleDetailPage(textId: 1)));
    await tester.pumpAndSettle();

    expect(find.byType(Chip), findsNothing);
    expect(find.text('背景介绍'), findsNothing);
  });

  testWidgets('暗色模式：背景使用深色宣纸色', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    settingsCtrl.setDarkMode(true);
    coord.text = _text();
    await tester.pumpWidget(wrap(const ArticleDetailPage(textId: 1)));
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppTheme.darkPaper);
  });

  testWidgets('点击开始阅读：加载文章并返回上一页', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    coord.text = _text();
    await tester.pumpWidget(wrap(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ArticleDetailPage(textId: 1)),
            ),
            child: const Text('进详情'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('进详情'));
    await tester.pumpAndSettle();
    expect(find.text('开始阅读'), findsOneWidget);

    await tester.tap(find.text('开始阅读'));
    await tester.pumpAndSettle();

    expect(coord.loadCalls, 1);
    expect(find.text('进详情'), findsOneWidget);
    expect(find.text('开始阅读'), findsNothing);
  });

  testWidgets('在读另一篇未满30秒：弹确认框，取消则留在详情页', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    coord.text = _text();
    final other = ChineseText(
      id: 2,
      title: '前赤壁赋',
      author: '苏轼',
      dynasty: '宋',
      content: '壬戌之秋，七月既望。',
      charCount: 100,
      difficulties: List.filled(10, 0.5),
    );
    readingCtrl.loadText(other);
    await tester.pumpWidget(wrap(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ArticleDetailPage(textId: 1)),
            ),
            child: const Text('进详情'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('进详情'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('开始阅读'));
    await tester.pumpAndSettle();
    expect(find.text('确认切换'), findsOneWidget);
    expect(find.text('当前文章阅读未满30秒，确定放弃？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(coord.loadCalls, 0);
    expect(find.text('开始阅读'), findsOneWidget);
    readingCtrl.pauseTimer();
  });

  testWidgets('在读另一篇未满30秒：确认放弃则丢弃并切换', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    coord.text = _text();
    final other = ChineseText(
      id: 2,
      title: '前赤壁赋',
      author: '苏轼',
      dynasty: '宋',
      content: '壬戌之秋，七月既望。',
      charCount: 100,
      difficulties: List.filled(10, 0.5),
    );
    readingCtrl.loadText(other);
    await tester.pumpWidget(wrap(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ArticleDetailPage(textId: 1)),
            ),
            child: const Text('进详情'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('进详情'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('开始阅读'));
    await tester.pumpAndSettle();
    expect(find.text('确认切换'), findsOneWidget);

    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();

    expect(coord.loadCalls, 1);
    expect(readingCtrl.isReading, isFalse);
    expect(find.text('进详情'), findsOneWidget);
    readingCtrl.pauseTimer();
  });

  testWidgets('在读同一篇：无确认弹窗直接切换', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    coord.text = _text();
    readingCtrl.loadText(_text());
    await tester.pumpWidget(wrap(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ArticleDetailPage(textId: 1)),
            ),
            child: const Text('进详情'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('进详情'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('开始阅读'));
    await tester.pumpAndSettle();

    expect(find.text('确认切换'), findsNothing);
    expect(coord.loadCalls, 1);
    readingCtrl.pauseTimer();
  });

  testWidgets('返回箭头：退回上一页', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    coord.text = _text();
    await tester.pumpWidget(wrap(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ArticleDetailPage(textId: 1)),
            ),
            child: const Text('进详情'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('进详情'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('进详情'), findsOneWidget);
    expect(find.text('开始阅读'), findsNothing);
  });
}