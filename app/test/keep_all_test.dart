import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/widgets/keep_all.dart';

const _j = wordJoiner;

/// [s] with a joiner between every two characters.
String _joined(String s) => s.split('').join(_j);

void main() {
  group('keepAll', () {
    test('joins the syllables of a word, not the words', () {
      expect(keepAll('증명하고, 지켜보세요.'), '${_joined('증명하고,')} ${_joined('지켜보세요.')}');
    });

    test('leaves text without Hangul as it is', () {
      const en = 'Prove it, then watch.';
      expect(identical(keepAll(en), en), isTrue);
      expect(keepAll('先证明，再看。'), '先证明，再看。');
      expect(keepAll(''), '');
    });

    test('joins Hangul to Latin, digits and brackets beside it', () {
      expect(keepAll('AI가'), 'AI$_j가'); // only next to Hangul
      expect(keepAll('3개'), _joined('3개'));
      expect(keepAll('(강의)를'), _joined('(강의)를'));
    });

    test('keeps spaces, dashes and slashes as places to break', () {
      expect(keepAll('가 나'), '가 나');
      expect(keepAll('가\n나'), '가\n나');
      expect(keepAll('가—나'), '가—나');
      expect(keepAll('가/나'), '가/나');
    });

    test('is idempotent', () {
      const s = '무엇을 할까요? (강의계획서)';
      expect(keepAll(keepAll(s)), keepAll(s));
    });

    test('changes nothing once the joiners are taken out', () {
      const s = '오늘은 무엇을 할까요? AI와 3개의 강의계획서.';
      expect(keepAll(s).replaceAll(_j, ''), s);
    });
  });

  testWidgets('a narrow Korean line breaks only at spaces', (tester) async {
    const s = '설명할 수 있을 때까지 증명하고, 지켜보세요.';
    final painter = TextPainter(
      text: TextSpan(text: keepAll(s), style: const TextStyle(fontSize: 20)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 130);
    final text = keepAll(s);
    var start = 0;
    final lines = <String>[];
    for (final line in painter.computeLineMetrics()) {
      final end = painter.getLineBoundary(TextPosition(offset: start)).end;
      lines.add(text.substring(start, end).replaceAll(_j, '').trim());
      start = end;
      if (line.lineNumber > 20) break;
    }
    painter.dispose();
    expect(lines.length, greaterThan(1));
    final words = s.split(' ');
    for (final line in lines.where((l) => l.isNotEmpty)) {
      for (final w in line.split(' ')) {
        expect(words, contains(w), reason: 'line "$line" splits a word');
      }
    }
  });
}
