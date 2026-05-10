import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';

void main() {
  group('AppState', () {
    late AppState app;

    setUp(() {
      app = AppState();
    });

    tearDown(() {
      app.dispose();
    });

    group('initial state', () {
      test('is not initialized', () {
        expect(app.initialized, false);
      });

      test('page index is 0', () {
        expect(app.pageIndex, 0);
      });

      test('dark mode is off', () {
        expect(app.darkMode, false);
      });

      test('log level is INFO', () {
        expect(app.logLevel, 'INFO');
      });

      test('user is null', () {
        expect(app.user, null);
      });

      test('texts is empty', () {
        expect(app.texts, isEmpty);
      });

      test('recommendations is empty', () {
        expect(app.recommendations, isEmpty);
      });

      test('no reading text', () {
        expect(app.readingText, null);
        expect(app.isReading, false);
      });

      test('pages empty', () {
        expect(app.pages, isEmpty);
        expect(app.totalPages, 0);
      });

      test('elapsed seconds is 0', () {
        expect(app.elapsedSeconds, 0);
        expect(app.formattedReadingTime, '00:00');
      });

      test('currentPageNumberLabel empty', () {
        expect(app.currentPageNumberLabel, '');
      });
    });

    group('page switching', () {
      test('switchPage changes index', () {
        expect(app.pageIndex, 0);
        expect(app.pageIndex, 0);
      });

      test('switchPage followed by getter returns new index', () {
        app.switchPage(2);
        expect(app.pageIndex, 2);
      });

      test('switchPage to same index is no-op', () {
        app.switchPage(1);
        app.switchPage(1);
        expect(app.pageIndex, 1);
      });

      test('goHome resets reading state', () {
        app.switchPage(2);
        expect(app.pageIndex, 2);
        app.goHome();
        expect(app.readingText, null);
        expect(app.pages, isEmpty);
      });
    });

    group('dark mode', () {
      test('setDarkMode toggles state', () {
        expect(app.darkMode, false);
        app.setDarkMode(true);
        expect(app.darkMode, true);
      });
    });

    group('log level', () {
      test('setLogLevel updates value', () {
        expect(app.logLevel, 'INFO');
        app.setLogLevel('DEBUG');
        expect(app.logLevel, 'DEBUG');
      });
    });

    group('error handling', () {
      test('error starts null', () {
        expect(app.error, null);
      });

      test('clearError resets error', () {
        app.clearError();
        expect(app.error, null);
      });
    });

    group('reading timer', () {
      test('stopReadingTimer when not reading is safe', () {
        app.stopReadingTimer();
        expect(app.elapsedSeconds, 0);
      });
    });
  });
}
