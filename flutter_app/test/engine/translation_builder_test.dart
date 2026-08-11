import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/translation_builder.dart';

void main() {
  const mark = TranslationBuilder.mark;

  group('TranslationBuilder.buildInterleaved', () {
    test('对齐段交错输出原文‖译文交替', () {
      const content = '原文一\n\n原文二';
      const translation = '译文一\n\n译文二';
      final segs = TranslationBuilder.buildInterleaved(content, translation);
      expect(segs, [
        '原文一',
        '$mark译文一$mark',
        '原文二',
        '$mark译文二$mark',
      ]);
    });

    test('译者名段并入前一段（段尾追加）', () {
      const content = '原文一\n\n原文二';
      const translation = '译文一\n\n译文二\n\n（李梦生）';
      final segs = TranslationBuilder.buildInterleaved(content, translation);
      expect(segs.length, 4);
      expect(segs[1], '$mark译文一$mark');
      expect(segs[3], '$mark译文二（李梦生）$mark');
    });

    test('译者名段在段首无前段则独立成段（防御分支）', () {
      const content = '原文一';
      const translation = '（李梦生）\n\n译文二';
      final segs = TranslationBuilder.buildInterleaved(content, translation);
      expect(segs.length, 2);
      expect(segs[1], '$mark（李梦生）译文二$mark');
    });

    test('非译者名括号段不并入', () {
      const content = '原文一';
      const translation = '译文（含括号）\n\n（顾易生　李笑野）';
      final segs = TranslationBuilder.buildInterleaved(content, translation);
      expect(segs.length, 2);
      expect(segs[1], '$mark译文（含括号）（顾易生　李笑野）$mark');
    });

    test('译文段数少：多余原文段配空译文段', () {
      const content = '原文一\n\n原文二\n\n原文三';
      const translation = '译文一\n\n译文二';
      final segs = TranslationBuilder.buildInterleaved(content, translation);
      expect(segs.length, 6);
      expect(segs[0], '原文一');
      expect(segs[1], '$mark译文一$mark');
      expect(segs[2], '原文二');
      expect(segs[3], '$mark译文二$mark');
      expect(segs[4], '原文三');
      expect(segs[5], '');
    });

    test('译文段数多：多余段并入前一段', () {
      const content = '原文一\n\n原文二';
      const translation = '译文一\n\n译文二\n\n译文三';
      final segs = TranslationBuilder.buildInterleaved(content, translation);
      expect(segs.length, 4);
      expect(segs[3], '$mark译文二译文三$mark');
    });

    test('译文为空降级为纯原文（不崩溃）', () {
      const content = '原文一\n\n原文二';
      final segs = TranslationBuilder.buildInterleaved(content, '');
      expect(segs, ['原文一', '原文二']);
    });

    test('空原文返回空列表', () {
      expect(TranslationBuilder.buildInterleaved('', '译文'), isEmpty);
    });

    test('原文单段译文单段', () {
      final segs = TranslationBuilder.buildInterleaved('原文一', '译文一');
      expect(segs, ['原文一', '$mark译文一$mark']);
    });
  });

  group('TranslationBuilder.toInterleavedText', () {
    test('段间以换行连接', () {
      final text = TranslationBuilder.toInterleavedText(
          ['原文一', '$mark译文一$mark']);
      expect(text, '原文一\n$mark译文一$mark');
    });

    test('空列表返回空字符串', () {
      expect(TranslationBuilder.toInterleavedText([]), '');
    });
  });
}
