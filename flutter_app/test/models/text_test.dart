import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';

void main() {
  group('ChineseText', () {
    test('fromInfo creates summary without content', () {
      final text = ChineseText.fromInfo(1, '论语', '孔子', '春秋');
      expect(text.id, 1);
      expect(text.title, '论语');
      expect(text.author, '孔子');
      expect(text.dynasty, '春秋');
      expect(text.content, '');
      expect(text.difficulties, isEmpty);
      expect(text.averageDifficulty, 0);
    });

    test('fromDetail creates full record', () {
      final text = ChineseText.fromDetail(
        1, '论语', '孔子', '春秋', '子曰：学而时习之',
        [0.3, 0.2, 0.4, 0.1, 0.5, 0.6, 0.7, 0.8, 0.9, 0.0],
      );
      expect(text.id, 1);
      expect(text.content, '子曰：学而时习之');
      expect(text.difficulties.length, 10);
      expect(text.difficulties[2], 0.4);
    });

    test('averageDifficulty computes correctly', () {
      final text = ChineseText.fromDetail(
        1, 'test', 'author', '唐', '',
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5],
      );
      expect(text.averageDifficulty, 0.05);
    });

    test('const constructor equality', () {
      const a = ChineseText(
        id: 1, title: '论语', author: '孔子', dynasty: '春秋');
      const b = ChineseText(
        id: 1, title: '论语', author: '孔子', dynasty: '春秋');
      expect(a.id, b.id);
      expect(a.title, b.title);
    });
  });

  group('RecommendResult', () {
    test('holds text and probability', () {
      final text = ChineseText.fromInfo(5, '孟子', '孟轲', '战国');
      final result = RecommendResult(text: text, probability: 0.85);
      expect(result.text.id, 5);
      expect(result.probability, 0.85);
    });
  });
}
