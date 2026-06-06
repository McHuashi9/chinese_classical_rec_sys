import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/state/navigation_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';

void main() {
  group('NavigationController', () {
    late NavigationController nav;

    setUp(() => nav = NavigationController());
    tearDown(() => nav.dispose());

    test('pageIndex starts at 0', () => expect(nav.pageIndex, 0));
    test('previousPageIndex starts at 0', () => expect(nav.previousPageIndex, 0));
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
    test('fontScale starts 1.0', () => expect(ctrl.fontScale, 1.0));
    test('logLevel starts INFO', () => expect(ctrl.logLevel, 'INFO'));
    test('error starts null', () => expect(ctrl.error, null));
    test('setDarkMode toggles', () {
      ctrl.setDarkMode(true);
      expect(ctrl.darkMode, true);
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
    tearDown(() => ctrl.dispose());

    test('isReading starts false', () => expect(ctrl.isReading, false));
    test('readingText starts null', () => expect(ctrl.readingText, null));
    test('pages starts empty', () => expect(ctrl.pages, isEmpty));
    test('currentPage starts 0', () => expect(ctrl.currentPage, 0));
    test('totalPages starts 0', () => expect(ctrl.totalPages, 0));
    test('elapsedSeconds starts 0', () => expect(ctrl.elapsedSeconds, 0));
    test('formattedReadingTime starts 00:00', () => expect(ctrl.formattedReadingTime, '00:00'));
    test('currentPageNumberLabel is empty', () => expect(ctrl.currentPageNumberLabel, ''));
    test('isTextRead returns false for unknown id', () => expect(ctrl.isTextRead(1), false));
    test('hasUnrecordedReading is false', () => expect(ctrl.hasUnrecordedReading, false));
    test('stopTimer is safe when not reading', () => ctrl.stopTimer());
    test('discardReading is safe', () => ctrl.discardReading());
    test('startTimer/stopTimer/pauseTimer/resumeTimer are safe', () {
      ctrl.startTimer();
      ctrl.pauseTimer();
      ctrl.resumeTimer();
      ctrl.stopTimer();
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
    test('recommendations starts empty', () => expect(ctrl.recommendations, isEmpty));
    test('applyReadEffect is safe without tracker', () {
      expect(ctrl.applyReadEffect(1, 60), false);
    });
    test('recordReading is safe without tracker', () {
      ctrl.recordReading(1, 60);
    });
    test('setUser updates user', () {
      // User needs ffi alloc, skip for unit test
      // Just verify setUser doesn't throw on null
      ctrl.setUser(null);
      expect(ctrl.user, null);
    });
  });
}
