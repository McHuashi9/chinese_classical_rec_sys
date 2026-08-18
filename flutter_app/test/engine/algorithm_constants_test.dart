import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/algorithm_constants.dart';

void main() {
  group('minReadTimeSeconds', () {
    test('无字数时兜底 30 秒', () {
      expect(minReadTimeSeconds(0), 30.0);
      expect(minReadTimeSeconds(-1), 30.0);
    });

    test('按 T = charCount / v_max * 60 计算', () {
      expect(minReadTimeSeconds(150), 60.0);
      expect(minReadTimeSeconds(50), 20.0);
      expect(minReadTimeSeconds(1000), 400.0);
    });
  });
}
