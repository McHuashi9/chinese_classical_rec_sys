import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/profile_repository.dart';

void main() {
  group('normalizeProfileName', () {
    test('trim 后返回原名', () {
      expect(normalizeProfileName('  小明  '), '小明');
    });

    test('空串返回 null', () {
      expect(normalizeProfileName(''), isNull);
      expect(normalizeProfileName('   '), isNull);
    });

    test('超过 63 字节返回 null', () {
      expect(normalizeProfileName('长' * 22), isNull); // 22 * 3 = 66 字节
      expect(normalizeProfileName('长' * 21), '长' * 21); // 21 * 3 = 63 字节
    });

    test('maxProfileNameBytes 为 63', () {
      expect(maxProfileNameBytes, 63);
    });
  });
}
