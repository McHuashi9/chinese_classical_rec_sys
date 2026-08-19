import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/bridge/c_types.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/pages/settings_page.dart';
import 'package:chinese_classical_rec_sys/pages/my_page.dart';
import 'package:chinese_classical_rec_sys/pages/read_hub_page.dart';
import 'package:chinese_classical_rec_sys/service/history_service.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

Widget _wrap(Widget child) {
  final navCtrl = NavigationController();
  final settingsCtrl = SettingsController();
  final readTracker = ReadTracker();
  final readingCtrl = ReadingController(readTracker);
  final userCtrl = UserController();
  final coord = AppCoordinator(
    navCtrl: navCtrl,
    settingsCtrl: settingsCtrl,
    readingCtrl: readingCtrl,
    userCtrl: userCtrl,
    readTracker: readTracker,
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: navCtrl),
      ChangeNotifierProvider.value(value: settingsCtrl),
      ChangeNotifierProvider.value(value: readingCtrl),
      ChangeNotifierProvider.value(value: userCtrl),
      Provider.value(value: coord),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

class _EmptyHistoryCoordinator extends AppCoordinator {
  _EmptyHistoryCoordinator({
    required super.navCtrl,
    required super.settingsCtrl,
    required super.readingCtrl,
    required super.userCtrl,
    required super.readTracker,
  });

  @override
  int getTotalReadCount() => 0;
}

class _HistoryCoordinator extends AppCoordinator {
  _HistoryCoordinator({
    required super.navCtrl,
    required super.settingsCtrl,
    required super.readingCtrl,
    required super.userCtrl,
    required super.readTracker,
  });

  @override
  int getTotalReadCount() => 1;

  @override
  List<ReadingRecord> getRecentHistory() => [];

  @override
  ReadingStats getReadingStats() => const ReadingStats(
        totalSeconds: 0,
        totalTexts: 0,
        dailyAvgSeconds: 0,
        longestStreak: 0,
      );
}

class _ReviewCountTracker implements QuizTracker {
  final int due;
  final int total;
  _ReviewCountTracker({required this.due, required this.total});

  @override
  (User?, bool?) applyQuiz(User user, int questionId, int choice,
          {bool isReview = false}) =>
      (null, null);

  @override
  User? applyRead(User user, int textId, double readTime) => null;

  @override
  User? prune(User user) => null;

  @override
  QuizBatch getQuestionsForText(int textId) => QuizBatch([]);

  @override
  List<ReviewItem> getDueReviews(int textId) => [];

  @override
  int getDueReviewCount(int textId) => due;

  @override
  int getTotalReviewCount(int textId) => total;

  @override
  List<Question> getQuestionsByIds(List<int> ids) => [];

  @override
  QuizAttemptSummary? getAttemptSummary(int textId) => null;

  @override
  void disposeQuestions(List<Question> questions) {}
}

class _F9QuizTracker implements QuizTracker {
  final List<Question> questions;
  _F9QuizTracker(this.questions);

  @override
  (User?, bool?) applyQuiz(User user, int questionId, int choice,
          {bool isReview = false}) =>
      (null, null);

  @override
  User? applyRead(User user, int textId, double readTime) => null;

  @override
  User? prune(User user) => null;

  @override
  QuizBatch getQuestionsForText(int textId) => QuizBatch(questions);

  @override
  List<ReviewItem> getDueReviews(int textId) => [];

  @override
  int getDueReviewCount(int textId) => 0;

  @override
  int getTotalReviewCount(int textId) => 0;

  @override
  List<Question> getQuestionsByIds(List<int> ids) => [];

  @override
  QuizAttemptSummary? getAttemptSummary(int textId) =>
      questions.isEmpty ? null : QuizAttemptSummary(questions.length, 0, 0);

  @override
  void disposeQuestions(List<Question> questions) {}
}

class _CountingCoordinator extends AppCoordinator {
  _CountingCoordinator({
    required super.navCtrl,
    required super.settingsCtrl,
    required super.readingCtrl,
    required super.userCtrl,
    required super.readTracker,
  });

  int finishCount = 0;

  @override
  void finishReadingSession() {
    finishCount++;
    super.finishReadingSession();
  }
}

List<Question> _f9Question() {
  final block = calloc<QuestionData>(1);
  block.ref.id = 1;
  block.ref.textId = 1;
  return [Question(block, owner: block)];
}

void main() {
  group('SettingsPage', () {
    testWidgets('renders appearance and about cards', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(_wrap(const SettingsPage()));
      await tester.pumpAndSettle();

      expect(find.text('设置'), findsOneWidget);
      expect(find.text('关于'), findsOneWidget);
      expect(find.text('用户档案'), findsOneWidget);
      expect(find.text('外观'), findsOneWidget);
      expect(find.text('日志'), findsOneWidget);
      expect(find.text('数据与反馈'), findsOneWidget);
      expect(find.text('v${AppCoordinator.currentVersion}'), findsOneWidget);
      expect(find.text('内容数据版本'), findsOneWidget);
      expect(find.text('数据库格式版本'), findsOneWidget);
      expect(find.text('存储状态'), findsOneWidget);
      expect(find.text('更新日志'), findsOneWidget);
      expect(find.text('公告 / 作者的话'), findsOneWidget);
      expect(find.text('反馈 Bug / 意见'), findsOneWidget);
      expect(find.text('导出学习数据'), findsOneWidget);
    });

    testWidgets('点击导出学习数据且引擎未就绪时提示', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(_wrap(const SettingsPage()));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('导出学习数据'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出学习数据'));
      await tester.pumpAndSettle();

      expect(find.text('核心引擎未就绪，无法导出'), findsOneWidget);
    });

    testWidgets('桌面平台显示打开日志目录按钮', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      try {
        await tester.pumpWidget(_wrap(const SettingsPage()));
        await tester.pumpAndSettle();

        expect(find.text('打开日志目录'), findsOneWidget);
        expect(find.text('移动端日志已包含在反馈中'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('移动平台显示日志已包含在反馈中', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      try {
        await tester.pumpWidget(_wrap(const SettingsPage()));
        await tester.pumpAndSettle();

        expect(find.text('打开日志目录'), findsNothing);
        expect(find.text('移动端日志已包含在反馈中'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('dark mode toggle switches theme', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final settingsCtrl = SettingsController();
      final navCtrl = NavigationController();
      final readTracker = ReadTracker();
      final readingCtrl = ReadingController(readTracker);
      final userCtrl = UserController();
      final coord = AppCoordinator(
        navCtrl: navCtrl,
        settingsCtrl: settingsCtrl,
        readingCtrl: readingCtrl,
        userCtrl: userCtrl,
        readTracker: readTracker,
      );
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: settingsCtrl,
          builder: (context, _) => MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: navCtrl),
              ChangeNotifierProvider.value(value: settingsCtrl),
              ChangeNotifierProvider.value(value: readingCtrl),
              ChangeNotifierProvider.value(value: userCtrl),
              Provider.value(value: coord),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme(ScreenSize.medium, 1.0,
                  accentColor: AppTheme.vermilion),
              darkTheme: AppTheme.darkTheme(ScreenSize.medium, 1.0,
                  accentColor: AppTheme.vermilion),
              themeMode:
                  settingsCtrl.darkMode ? ThemeMode.dark : ThemeMode.light,
              home: const Scaffold(body: SettingsPage()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(settingsCtrl.darkMode, false);
      expect(
        Theme.of(tester.element(find.text('设置'))).brightness,
        Brightness.light,
      );

      await tester.tap(find.text('暗色模式'));
      await tester.pumpAndSettle();

      expect(settingsCtrl.darkMode, true);
      expect(
        Theme.of(tester.element(find.text('设置'))).brightness,
        Brightness.dark,
      );
    });
  });

  group('ReadHubPage', () {
    testWidgets('shows library tab by default', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(_wrap(const ReadHubPage()));
      await tester.pumpAndSettle();

      expect(find.text('文库'), findsOneWidget);
    });

    testWidgets('阅读完成弹窗选择“下次再说”：只结算一次并退出阅读', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final questions = _f9Question();
      addTearDown(() => calloc.free(questions.first.owner));

      final navCtrl = NavigationController();
      final settingsCtrl = SettingsController();
      final readTracker = ReadTracker();
      final readingCtrl = ReadingController(readTracker);
      readingCtrl.loadText(ChineseText(
        id: 1,
        title: '岳阳楼记',
        author: '范仲淹',
        dynasty: '宋',
        source: '古文观止',
        content: '庆历四年春，滕子京谪守巴陵郡。',
        charCount: 20,
        difficulties: List.filled(10, 0.5),
      ));
      final userCtrl = UserController();
      userCtrl.initTracker(_F9QuizTracker(questions));
      userCtrl.setUser(User.allocate(calloc));
      addTearDown(userCtrl.dispose);
      final coord = _CountingCoordinator(
        navCtrl: navCtrl,
        settingsCtrl: settingsCtrl,
        readingCtrl: readingCtrl,
        userCtrl: userCtrl,
        readTracker: readTracker,
      );
      addTearDown(readingCtrl.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: navCtrl),
            ChangeNotifierProvider.value(value: settingsCtrl),
            ChangeNotifierProvider.value(value: readingCtrl),
            ChangeNotifierProvider.value(value: userCtrl),
            Provider<AppCoordinator>.value(value: coord),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme(ScreenSize.medium, 1.0,
                accentColor: AppTheme.vermilion),
            darkTheme: AppTheme.darkTheme(ScreenSize.medium, 1.0,
                accentColor: AppTheme.vermilion),
            themeMode:
                settingsCtrl.darkMode ? ThemeMode.dark : ThemeMode.light,
            home: const Scaffold(body: ReadHubPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 推进到超过最低阅读时间，使“完成”按钮可用。
      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();

      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.text('下次再说'), findsOneWidget);

      await tester.tap(find.text('下次再说'));
      await tester.pumpAndSettle();

      expect(coord.finishCount, 1);
      expect(readingCtrl.isReading, isFalse);
    });
  });

  group('MyPage', () {
    testWidgets('shows loader when user is null', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(_wrap(const MyPage()));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('无历史且能力全零时显示引导空态', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final navCtrl = NavigationController();
      final settingsCtrl = SettingsController();
      final readTracker = ReadTracker();
      final readingCtrl = ReadingController(readTracker);
      final userCtrl = UserController()..setUser(User.allocate(calloc));
      final coord = _EmptyHistoryCoordinator(
        navCtrl: navCtrl,
        settingsCtrl: settingsCtrl,
        readingCtrl: readingCtrl,
        userCtrl: userCtrl,
        readTracker: readTracker,
      );
      addTearDown(() {
        readingCtrl.dispose();
        userCtrl.dispose();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: navCtrl),
            ChangeNotifierProvider.value(value: settingsCtrl),
            ChangeNotifierProvider.value(value: readingCtrl),
            ChangeNotifierProvider.value(value: userCtrl),
            Provider<AppCoordinator>.value(value: coord),
          ],
          child: const MaterialApp(home: Scaffold(body: MyPage())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('去读一篇文章开始吧'), findsOneWidget);
      expect(find.text('阅读达到本文最低阅读时间后，这里会展示你的能力画像与阅读统计'), findsOneWidget);
    });

    testWidgets('错题卡片显示错题总数与到期数', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final navCtrl = NavigationController();
      final settingsCtrl = SettingsController();
      final readTracker = ReadTracker();
      final readingCtrl = ReadingController(readTracker);
      final userCtrl = UserController()
        ..initTracker(_ReviewCountTracker(due: 2, total: 5))
        ..setUser(User.allocate(calloc));
      final coord = _HistoryCoordinator(
        navCtrl: navCtrl,
        settingsCtrl: settingsCtrl,
        readingCtrl: readingCtrl,
        userCtrl: userCtrl,
        readTracker: readTracker,
      );
      addTearDown(() {
        readingCtrl.dispose();
        userCtrl.dispose();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: navCtrl),
            ChangeNotifierProvider.value(value: settingsCtrl),
            ChangeNotifierProvider.value(value: readingCtrl),
            ChangeNotifierProvider.value(value: userCtrl),
            Provider<AppCoordinator>.value(value: coord),
          ],
          child: const MaterialApp(home: Scaffold(body: MyPage())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('错题复习 · 共 5 题 · 2 道到期'), findsOneWidget);
    });
  });
}
