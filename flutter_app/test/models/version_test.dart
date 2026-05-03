import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/models/version.dart';

void main() {
  group('Version.parse', () {
    test('parses plain version', () {
      final v = Version.parse('0.2.0');
      expect(v.major, 0);
      expect(v.minor, 2);
      expect(v.patch, 0);
      expect(v.toString(), '0.2.0');
    });

    test('parses v-prefixed version', () {
      final v = Version.parse('v0.2.0');
      expect(v.major, 0);
      expect(v.minor, 2);
      expect(v.patch, 0);
    });

    test('parses V-prefixed version', () {
      final v = Version.parse('V1.0.0');
      expect(v.major, 1);
      expect(v.minor, 0);
      expect(v.patch, 0);
    });

    test('strips prerelease suffix', () {
      final v = Version.parse('0.2.0-beta');
      expect(v.major, 0);
      expect(v.minor, 2);
      expect(v.patch, 0);
    });

    test('parses v-prefixed with prerelease', () {
      final v = Version.parse('v2.0.0-rc1');
      expect(v.major, 2);
      expect(v.minor, 0);
      expect(v.patch, 0);
    });

    test('throws FormatException on empty string', () {
      expect(() => Version.parse(''), throwsA(isA<FormatException>()));
    });

    test('throws FormatException on non-version string', () {
      expect(() => Version.parse('abc'), throwsA(isA<FormatException>()));
    });
  });

  group('Version.compareTo', () {
    test('equal versions', () {
      expect(Version.parse('0.2.0').compareTo(Version.parse('0.2.0')), 0);
    });

    test('greater major', () {
      expect(Version.parse('1.0.0').compareTo(Version.parse('0.9.9')), greaterThan(0));
    });

    test('greater minor', () {
      expect(Version.parse('0.3.0').compareTo(Version.parse('0.2.9')), greaterThan(0));
    });

    test('greater patch', () {
      expect(Version.parse('0.2.1').compareTo(Version.parse('0.2.0')), greaterThan(0));
    });

    test('less than', () {
      expect(Version.parse('0.1.0').compareTo(Version.parse('0.2.0')), lessThan(0));
    });
  });

  group('Version operators', () {
    test('> operator', () {
      expect(Version.parse('0.3.0') > Version.parse('0.2.0'), true);
      expect(Version.parse('0.2.0') > Version.parse('0.3.0'), false);
    });

    test('< operator', () {
      expect(Version.parse('0.1.0') < Version.parse('0.2.0'), true);
      expect(Version.parse('0.2.0') < Version.parse('0.1.0'), false);
    });

    test('== operator', () {
      expect(Version.parse('0.2.0') == Version.parse('0.2.0'), true);
      expect(Version.parse('v0.2.0') == Version.parse('0.2.0'), true);
    });
  });
}
