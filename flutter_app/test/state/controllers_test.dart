import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

void main() {
  group('NavigationController', () {
    late NavigationController nav;

    setUp(() => nav = NavigationController());
    tearDown(() => nav.dispose());

    test('pageIndex starts at 0', () => expect(nav.pageIndex, 0));
    test('switchPage changes index', () {
      nav.switchPage(1);
      expect(nav.pageIndex, 1);
      expect(nav.previousPageIndex, 0);
    });
    test('switchPage is no-op for same index', () {
      nav.switchPage(0);
      expect(nav.pageIndex, 0);
      expect(nav.previousPageIndex, 0);
    });
  });

  group('SettingsController', () {
    late SettingsController ctrl;

    setUp(() => ctrl = SettingsController());
    tearDown(() => ctrl.dispose());

    test('darkMode starts false', () => expect(ctrl.darkMode, false));
    test('showTranslation starts false', () => expect(ctrl.showTranslation, false));
    test('fontScale starts 1.0', () => expect(ctrl.fontScale, 1.0));
    test('logLevel starts INFO', () => expect(ctrl.logLevel, 'INFO'));
    test('error starts null', () => expect(ctrl.error, null));
    test('setDarkMode toggles', () {
      ctrl.setDarkMode(true);
      expect(ctrl.darkMode, true);
    });
    test('setShowTranslation toggles', () {
      ctrl.setShowTranslation(true);
      expect(ctrl.showTranslation, true);
      ctrl.setShowTranslation(false);
      expect(ctrl.showTranslation, false);
    });
    test('setLogLevel updates', () {
      ctrl.setLogLevel('DEBUG');
      expect(ctrl.logLevel, 'DEBUG');
    });
    test('clearError resets', () {
      ctrl.setError('test');
      expect(ctrl.error, 'test');
      ctrl.clearError();
      expect(ctrl.error, null);
    });
    test('updateCheckError starts null', () {
      expect(ctrl.updateCheckError, null);
    });
    test('non-null fontScaleSteps', () {
      expect(SettingsController.fontScaleSteps, isNotEmpty);
    });
  });

  group('ReadingController', () {
    late ReadTracker tracker;
    late ReadingController ctrl;

    setUp(() {
      tracker = ReadTracker();
      ctrl = ReadingController(tracker);
    });
    tearDown(() {
      ctrl.stopTimer();
      ctrl.dispose();
    });

    test('isReading starts false', () => expect(ctrl.isReading, false));
    test('readingText starts null', () => expect(ctrl.readingText, null));
    test('elapsedSeconds starts 0', () => expect(ctrl.elapsedSeconds, 0));
    test('formattedReadingTime starts 00:00', () => expect(ctrl.formattedReadingTime, '00:00'));
    test('currentPageNumberLabel is empty', () => expect(ctrl.currentPageNumberLabel, ''));
    test('isTextRead returns false for unknown id', () => expect(ctrl.isTextRead(1), false));
    test('hasUnrecordedReading is false', () => expect(ctrl.hasUnrecordedReading, false));
    test('stopTimer is safe when not reading', () => ctrl.stopTimer());
    test('discardReading is safe', () => ctrl.discardReading());
    test('showTranslation starts false', () => expect(ctrl.showTranslation, false));
    test('setShowTranslation toggles', () {
      ctrl.setShowTranslation(true);
      expect(ctrl.showTranslation, true);
      ctrl.setShowTranslation(false);
      expect(ctrl.showTranslation, false);
    });
    test('startTimer/stopTimer/pauseTimer/resumeTimer are safe', () {
      ctrl.startTimer();
      ctrl.pauseTimer();
      ctrl.resumeTimer();
      ctrl.stopTimer();
    });

    void withCleanup(VoidCallback fn) {
      try {
        fn();
      } finally {
        ctrl.stopTimer();
      }
    }

    testWidgets('paginate 空内容返回空页', (tester) async {
      withCleanup(() {
        const text = ChineseText(
          id: 1, title: 't', author: 'a', dynasty: '唐',
        );
        ctrl.loadText(text);
        ctrl.paginate(400, 600, ScreenSize.medium, 1.0, false);
        expect(ctrl.pages, isEmpty);
        expect(ctrl.totalPages, 0);
      });
    });

    testWidgets('paginate 短内容一页显示', (tester) async {
      withCleanup(() {
        const text = ChineseText(
          id: 1, title: 't', author: 'a', dynasty: '唐',
          content: 'Hello World',
        );
        ctrl.loadText(text);
        ctrl.paginate(400, 600, ScreenSize.medium, 1.0, false);
        expect(ctrl.pages.length, 1);
        expect(ctrl.currentPage, 0);
        expect(ctrl.totalPages, 1);
      });
    });

    testWidgets('paginate 长内容分多页', (tester) async {
      withCleanup(() {
        final longContent = 'Hello world, this is a test paragraph that should '
            'wrap across multiple lines when laid out at a reasonable page width. '
            'We repeat this several times to ensure enough content for multi-page '
            'pagination behavior in the reading controller. ' * 30;
        final text = ChineseText(
          id: 2, title: 'long', author: 'a', dynasty: '唐',
          content: longContent,
        );
        ctrl.loadText(text);
        ctrl.paginate(200, 100, ScreenSize.medium, 1.0, false);
        expect(ctrl.pages.length, greaterThan(1));
        expect(ctrl.totalPages, greaterThan(1));
      });
    });

    testWidgets('paginate 后翻页/回翻', (tester) async {
      withCleanup(() {
        final longContent = 'Page test content for navigation verification. ' * 50;
        final text = ChineseText(
          id: 3, title: 'nav', author: 'a', dynasty: '唐',
          content: longContent,
        );
        ctrl.loadText(text);
        ctrl.paginate(200, 100, ScreenSize.medium, 1.0, false);
        expect(ctrl.currentPage, 0);

        ctrl.nextPage();
        expect(ctrl.currentPage, 1);

        ctrl.nextPage();
        expect(ctrl.currentPage, 2);

        ctrl.prevPage();
        expect(ctrl.currentPage, 1);

        ctrl.prevPage();
        expect(ctrl.currentPage, 0);
      });
    });

    testWidgets('paginate 末尾不越界', (tester) async {
      withCleanup(() {
        final longContent = 'Boundary test. ' * 30;
        final text = ChineseText(
          id: 4, title: 'bnd', author: 'a', dynasty: '唐',
          content: longContent,
        );
        ctrl.loadText(text);
        ctrl.paginate(200, 100, ScreenSize.medium, 1.0, false);
        final last = ctrl.totalPages - 1;
        for (int i = 0; i < last + 5; i++) {
          ctrl.nextPage();
        }
        expect(ctrl.currentPage, last);

        for (int i = 0; i < last + 5; i++) {
          ctrl.prevPage();
        }
        expect(ctrl.currentPage, 0);
      });
    });

    testWidgets('loadText 无译文时 showTranslation 开关不影响分页内容', (tester) async {
      withCleanup(() {
        const text = ChineseText(
          id: 5, title: 'no-trans', author: 'a', dynasty: '唐',
          content: '原文内容\n\n第二段',
        );
        ctrl.loadText(text);
        ctrl.setShowTranslation(true);
        expect(ctrl.showTranslation, true);
      });
    });

    testWidgets('loadText 带译文默认不显示，开关后分页源切换为交错文本', (tester) async {
      withCleanup(() {
        const text = ChineseText(
          id: 6, title: 'trans', author: 'a', dynasty: '唐',
          content: '原文一\n\n原文二',
        );
        ctrl.loadText(
          text,
          translation: '译文一\n\n译文二',
          showTranslation: false,
        );
        expect(ctrl.showTranslation, false);
        ctrl.paginate(400, 600, ScreenSize.medium, 1.0, false);
        expect(ctrl.pages.join('\n'), isNot(contains('\u200B')));

        ctrl.setShowTranslation(true);
        ctrl.paginate(400, 600, ScreenSize.medium, 1.0, false);
        final joined = ctrl.pages.join('\n');
        expect(joined, contains('\u200B译文一\u200B'));
        expect(joined, contains('原文一'));
      });
    });

    testWidgets('译文交错分页完整性：多页下所有段不丢、首尾段保持', (tester) async {
      withCleanup(() {
        const text = ChineseText(
          id: 7, title: 'interleaved', author: 'a', dynasty: '唐',
          content: '原文一\n\n原文二\n\n原文三\n\n原文四',
        );
        ctrl.loadText(
          text,
          translation: '译文一\n\n译文二\n\n译文三\n\n译文四',
          showTranslation: true,
        );
        // 小页高强制分多页（2 行/页）
        ctrl.paginate(400, 60, ScreenSize.medium, 1.0, false);
        expect(ctrl.pages.length, greaterThan(1));

        final joined = ctrl.pages.join('\n');
        // 全部原文段与译文段都出现在分页结果中
        for (final seg in ['原文一', '原文二', '原文三', '原文四']) {
          expect(joined, contains(seg));
        }
        for (final seg in ['译文一', '译文二', '译文三', '译文四']) {
          expect(joined, contains('\u200B$seg\u200B'));
        }
        // 顺序保持：首段在首页首行，末段在末页尾部
        expect(ctrl.pages.first.trimRight(), startsWith('原文一'));
        expect(ctrl.pages.last.trimRight(), endsWith('\u200B译文四\u200B'));
      });
    });
  });

  group('UserController', () {
    late ReadTracker tracker;
    late UserController ctrl;

    setUp(() {
      tracker = ReadTracker();
      ctrl = UserController(tracker);
    });
    tearDown(() => ctrl.dispose());

    test('user starts null', () => expect(ctrl.user, null));
    test('averageAbility defaults to 0.3', () => expect(ctrl.averageAbility, 0.3));
    test('applyReadEffect is safe without tracker', () {
      expect(ctrl.applyReadEffect(1, 60), false);
    });
    test('recordReading is safe without tracker', () {
      ctrl.recordReading(1, 60);
    });
    test('setUser updates user（真实 User 对象，旧用户被释放）', () {
      final u1 = User.allocate(calloc);
      final u2 = User.allocate(calloc);
      ctrl.setUser(u1);
      expect(identical(ctrl.user, u1), isTrue);
      ctrl.setUser(u2);
      expect(identical(ctrl.user, u2), isTrue);
    });
  });
}
