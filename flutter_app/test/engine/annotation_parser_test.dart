import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/engine/annotation_parser.dart';
import 'package:chinese_classical_rec_sys/engine/translation_builder.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

void main() {
  group('AnnotationParser.parse', () {
    test('空字符串返回空 map', () {
      expect(AnnotationParser.parse(''), {});
    });

    test('单条注解', () {
      expect(AnnotationParser.parse('〔1〕hello'), {1: 'hello'});
    });

    test('多条注解', () {
      final result = AnnotationParser.parse('〔1〕hello〔2〕world');
      expect(result, {1: 'hello', 2: 'world'});
    });

    test('带换行', () {
      const raw = '〔1〕第一行内容\n〔2〕第二行内容';
      expect(AnnotationParser.parse(raw), {
        1: '第一行内容',
        2: '第二行内容',
      });
    });

    test('注解后有尾部文本', () {
      final result = AnnotationParser.parse('〔1〕内容 后续补充');
      expect(result, {1: '内容 后续补充'});
    });

    test('数字编号正确解析', () {
      final result = AnnotationParser.parse('〔12〕十二〔123〕一百二十三');
      expect(result, {12: '十二', 123: '一百二十三'});
    });
  });

  group('AnnotationParser.parseEntry', () {
    test('语文课本格式 [word]内容', () {
      final entry = AnnotationParser.parseEntry('[字]释义内容');
      expect(entry.headword, '字');
      expect(entry.content, '释义内容');
    });

    test('古文观止格式 word：内容', () {
      final entry = AnnotationParser.parseEntry('字：释义内容');
      expect(entry.headword, '字');
      expect(entry.content, '释义内容');
    });

    test('fallback — 无匹配格式', () {
      final entry = AnnotationParser.parseEntry('无格式内容');
      expect(entry.headword, '');
      expect(entry.content, '无格式内容');
    });

    test('空方括号回退到 anthology 格式', () {
      final entry = AnnotationParser.parseEntry('[]内容');
      expect(entry.headword, '');
      expect(entry.content, '[]内容');
    });

    test('纯冒号开头回退', () {
      final entry = AnnotationParser.parseEntry('：内容');
      expect(entry.headword, '');
      expect(entry.content, '：内容');
    });

    test('空字符串', () {
      final entry = AnnotationParser.parseEntry('');
      expect(entry.headword, '');
      expect(entry.content, '');
    });
  });

  group('AnnotationParser.parseEntries', () {
    test('单条（无全角空格）— 与 parseEntry 一致', () {
      final result = AnnotationParser.parseEntries('字：释义内容');
      expect(result.length, 1);
      expect(result.single.headword, '字');
      expect(result.single.content, '释义内容');
    });

    test('语文课本格式多段', () {
      final result = AnnotationParser.parseEntries('[屠]屠户。\u3000[狼]狼犬。');
      expect(result.length, 2);
      expect(result[0].headword, '屠');
      expect(result[1].headword, '狼');
      expect(result[1].content, '狼犬。');
    });

    test('古文观止格式多词条', () {
      final result = AnnotationParser.parseEntries(
          '王：周襄王。\u3000宰孔：名孔，宰是官名。\u3000齐侯：齐桓公。');
      expect(result.length, 3);
      expect(result[0].headword, '王');
      expect(result[1].headword, '宰孔');
      expect(result[2].headword, '齐侯');
    });

    test('词头含注音括号', () {
      final result = AnnotationParser.parseEntries('乘堙（yīn因）：登上土堆。');
      expect(result.length, 1);
      expect(result[0].headword, '乘堙（yīn因）');
    });

    test('词头含顿号', () {
      final result =
          AnnotationParser.parseEntries('文、武：周文王与周武王。');
      expect(result.single.headword, '文、武');
    });

    test('无词头续段并入前一条', () {
      final result = AnnotationParser.parseEntries(
          '申：国名\u3000姜姓\u3000国土在今河南南阳市。');
      expect(result.length, 1);
      expect(result.single.headword, '申');
      expect(result.single.content, '国名　姜姓　国土在今河南南阳市。');
    });

    test('逗号式词头段并入前一条', () {
      final result = AnnotationParser.parseEntries(
          '贰于虢：指偏信虢公。\u3000虢，指西虢公，仕于周。');
      expect(result.length, 1);
      expect(result.single.headword, '贰于虢');
      expect(result.single.content, '指偏信虢公。　虢，指西虢公，仕于周。');
    });

    test('空字符串', () {
      expect(AnnotationParser.parseEntries(''), isEmpty);
    });

    test('整段无格式', () {
      final result = AnnotationParser.parseEntries('无格式内容');
      expect(result.length, 1);
      expect(result.single.headword, '');
      expect(result.single.content, '无格式内容');
    });
  });

  group('AnnotatedTextBuilder.build', () {
    final baseStyle = AppTheme.bodyReadingSize(ScreenSize.medium, 1.0);

    test('无标注 — 单个 TextSpan', () {
      final span = AnnotatedTextBuilder.build('纯文本', {}, baseStyle);
      expect(span.children!.length, 1);
      expect((span.children![0] as TextSpan).text, '纯文本');
    });

    test('有标注的 marker 获得 markerStyle', () {
      final span = AnnotatedTextBuilder.build('a〔1〕b', {1: '释义'}, baseStyle);
      final children = span.children!;
      expect(children.length, 3);
      expect((children[0] as TextSpan).text, 'a');
      expect((children[2] as TextSpan).text, 'b');

      final marker = children[1] as TextSpan;
      expect(marker.text, '〔1〕');
      expect(marker.style!.color, AppTheme.vermilion);
      expect(marker.style!.fontWeight, FontWeight.w600);
    });

    test('无对应 annotation 的 marker 用 baseStyle', () {
      final span = AnnotatedTextBuilder.build('〔1〕', {}, baseStyle);
      final marker = span.children![0] as TextSpan;
      expect(marker.text, '〔1〕');
      expect(marker.style!.color, isNot(AppTheme.vermilion));
    });

    test('多条标注', () {
      final span = AnnotatedTextBuilder.build(
        'a〔1〕b〔2〕c',
        {1: '一', 2: '二'},
        baseStyle,
      );
      expect(span.children!.length, 5);
      expect((span.children![0] as TextSpan).text, 'a');
      expect((span.children![1] as TextSpan).text, '〔1〕');
      expect((span.children![2] as TextSpan).text, 'b');
      expect((span.children![3] as TextSpan).text, '〔2〕');
      expect((span.children![4] as TextSpan).text, 'c');
    });

    test('尾部无文本', () {
      final span = AnnotatedTextBuilder.build('a〔1〕', {1: 'x'}, baseStyle);
      expect(span.children!.length, 2);
    });

    test('toPlainText 保持原文', () {
      final span = AnnotatedTextBuilder.build(
        '原文〔1〕内容', {1: '注'}, baseStyle,
      );
      expect(span.toPlainText(), '原文〔1〕内容');
    });

    group('译文样式（零宽字符标记）', () {
      const mark = TranslationBuilder.mark;

      test('标记内文本获得译文样式（浅色 stoneGreen 0.9x）', () {
        final span = AnnotatedTextBuilder.build(
          '原文段\n$mark译文段$mark',
          {},
          baseStyle,
        );
        final children = span.children!;
        expect(children.length, 2);
        expect((children[0] as TextSpan).text, '原文段\n');
        expect((children[0] as TextSpan).style, isNull);
        final transSpan = children[1] as TextSpan;
        expect(transSpan.text, '译文段');
        expect(transSpan.style!.color, AppTheme.stoneGreen);
        expect(
          transSpan.style!.fontSize,
          closeTo(baseStyle.fontSize! * 0.9, 0.001),
        );
      });

      test('深色模式用 darkInkSecondary', () {
        final span = AnnotatedTextBuilder.build(
          '$mark译文$mark',
          {},
          baseStyle,
          isDark: true,
        );
        final transSpan = span.children!.first as TextSpan;
        expect(transSpan.style!.color, AppTheme.darkInkSecondary);
      });

      test('标记字符本身不渲染', () {
        final span = AnnotatedTextBuilder.build(
          '$mark译$mark文',
          {},
          baseStyle,
        );
        expect(span.toPlainText(), '译文');
      });

      test('页尾无闭合标记：整段译文样式到结尾（容错）', () {
        final span = AnnotatedTextBuilder.build(
          '原文\n$mark未闭合译文',
          {},
          baseStyle,
        );
        final last = span.children!.last as TextSpan;
        expect(last.text, '未闭合译文');
        expect(last.style!.color, AppTheme.stoneGreen);
      });

      test('页首残留闭合标记忽略，后续正常', () {
        final span = AnnotatedTextBuilder.build(
          '$mark译$mark尾',
          {},
          baseStyle,
        );
        expect(span.toPlainText(), '译尾');
      });

      test('译文段内〔n〕不参与译文样式（原文段 marker 不受影响）', () {
        final span = AnnotatedTextBuilder.build(
          'a〔1〕b$mark译$mark',
          {1: '注'},
          baseStyle,
        );
        final marker = span.children![1] as TextSpan;
        expect(marker.text, '〔1〕');
        expect(marker.style!.color, AppTheme.vermilion);
      });
    });
  });

  group('AnnotatedTextBuilder.findAnnotationAtOffset', () {
    const page = '前文〔5〕后文';
    const annotations = {5: '注解'};

    test('在 marker 范围内返回编号', () {
      expect(
        AnnotatedTextBuilder.findAnnotationAtOffset(page, 2, annotations),
        5,
      );
      expect(
        AnnotatedTextBuilder.findAnnotationAtOffset(page, 4, annotations),
        5,
      );
    });

    test('在 marker 范围外返回 null', () {
      expect(
        AnnotatedTextBuilder.findAnnotationAtOffset(page, 0, annotations),
        isNull,
      );
      expect(
        AnnotatedTextBuilder.findAnnotationAtOffset(page, 6, annotations),
        isNull,
      );
    });

    test('无对应 annotation 的 marker 返回 null', () {
      expect(
        AnnotatedTextBuilder.findAnnotationAtOffset('〔3〕', 1, {}),
        isNull,
      );
    });
  });

  group('AnnotatedTextBuilder.markerSelection', () {
    const page = '前〔42〕后';

    test('已存在的 marker 返回正确 selection', () {
      final sel = AnnotatedTextBuilder.markerSelection(page, 42);
      expect(sel.baseOffset, 1);
      expect(sel.extentOffset, 5);
    });

    test('不存在的 marker 返回 collapsed(0)', () {
      final sel = AnnotatedTextBuilder.markerSelection(page, 99);
      expect(sel.baseOffset, 0);
      expect(sel.extentOffset, 0);
      expect(sel.isCollapsed, true);
    });

    test('多个 marker 中查找', () {
      final sel = AnnotatedTextBuilder.markerSelection('〔1〕〔2〕', 2);
      expect(sel.baseOffset, 3);
      expect(sel.extentOffset, 6);
    });
  });
}
