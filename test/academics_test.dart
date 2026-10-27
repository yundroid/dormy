import 'package:dormy/features/academics/assessments_page.dart';
import 'package:dormy/features/academics/ranking.dart';
import 'package:dormy/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('net hesabı', () {
    test('3 yanlış 1 doğruyu götürür', () {
      expect(netScore(12, 6), 10);
      expect(netScore(30, 9), 27);
      expect(netScore(0, 3), -1);
      expect(netScore(10, 1), closeTo(9.667, 0.001));
    });

    test('doğru/yanlış girişi çözümlenir, boş otomatik', () {
      expect(parseAnswer((correct: '', wrong: ''), 20), isNull);
      expect(parseAnswer((correct: '12', wrong: ''), 20), (correct: 12, wrong: 0));
      expect(parseAnswer((correct: '12', wrong: '6'), 20), (correct: 12, wrong: 6));
      expect(parseAnswer((correct: '15', wrong: '6'), 20), isA<InvalidAnswer>());
    });
  });

  group('sıralama', () {
    test('eşit puanlar aynı sırayı alır', () {
      final ranked = rankBy([('a', 80), ('b', 95), ('c', 80), ('d', 60)], (e) => e.$2, tieBreak: (e) => e.$1);
      expect(ranked.map((r) => (r.rank, r.item.$1)).toList(), [(1, 'b'), (2, 'a'), (2, 'c'), (4, 'd')]);
    });

    test('istatistik', () {
      final s = Stats.of([90, 70, 80]);
      expect(s.count, 3);
      expect(s.average, 80);
      expect(s.max, 90);
      expect(s.min, 70);
      expect(Stats.of(const <num>[]).average, isNull);
    });

    test('Türkçe sayı biçimi', () {
      expect(formatNumber(10.333333), '10,33');
      expect(formatNumber(92.5), '92,5');
      expect(formatNumber(100), '100');
    });
  });

  group('isim gizleme', () {
    test('baş harfler Türkçe büyük harfle', () {
      expect(initialsOf('ismail Can yılmaz'), 'İ. C. Y.');
      expect(initialsOf('  ırmak   Öz '), 'I. Ö.');
    });

    test('tek öğrenci modu', () {
      expect(maskName('Ahmet Y', NameMode.single, studentId: 'a', highlightId: 'a'), 'Ahmet Y');
      expect(maskName('Mehmet K', NameMode.single, studentId: 'b', highlightId: 'a'), '• • •');
      expect(maskName('Mehmet K', NameMode.full, studentId: 'b'), 'Mehmet K');
    });
  });

  test('özel modüller günlük giriş ekranına gitmez', () {
    expect(ModuleValueType.parse('trial_exam'), ModuleValueType.trialExam);
    expect(ModuleValueType.trialExam.route, '/trials');
    expect(ModuleValueType.score.route, isNull);
    expect(ModuleValueType.values.where((t) => t.isEntryType), hasLength(3));
  });
}
