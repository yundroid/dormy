import 'package:dormy/features/reports/report_logic.dart';
import 'package:dormy/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

DormModule _m(String id, ModuleValueType type, {double weight = 1, bool reports = true, int? max}) => DormModule(
      id: id,
      tenantId: 't',
      name: id,
      icon: 'checklist',
      scope: ModuleScope.general,
      valueType: type,
      minValue: max == null ? null : 1,
      maxValue: max,
      sessions: const ['Günlük'],
      isSystem: true,
      isActive: true,
      includeInReports: reports,
      weight: weight,
      sortOrder: 0,
    );

Student _s(String id) => Student(id: id, tenantId: 't', firstName: id, lastName: 'X', status: StudentStatus.active);

ReportCell _c(String s, String m, int count, double? percent, {double? raw, double? extra}) =>
    ReportCell(studentId: s, moduleId: m, count: count, percent: percent, raw: raw, extra: extra);

void main() {
  group('tarih aralıkları', () {
    // 29 Ekim 2026 Perşembe
    final today = DateTime(2026, 10, 29);

    test('bu hafta pazartesiden başlar', () {
      expect(rangeFor(RangePreset.thisWeek, today), (from: DateTime(2026, 10, 26), to: today));
    });

    test('geçen hafta', () {
      expect(rangeFor(RangePreset.lastWeek, today), (from: DateTime(2026, 10, 19), to: DateTime(2026, 10, 25)));
    });

    test('bu ay ve geçen ay', () {
      expect(rangeFor(RangePreset.thisMonth, today), (from: DateTime(2026, 10, 1), to: today));
      expect(rangeFor(RangePreset.lastMonth, today), (from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30)));
      expect(rangeFor(RangePreset.lastMonth, DateTime(2026, 1, 15)), (from: DateTime(2025, 12, 1), to: DateTime(2025, 12, 31)));
    });

    test('son 30 gün bugünü de içerir', () {
      final r = rangeFor(RangePreset.last30, today);
      expect(r.to.difference(r.from).inDays, 29);
    });
  });

  group('genel başarı', () {
    final att = _m('att', ModuleValueType.attendance);
    final bed = _m('bed', ModuleValueType.score, max: 5, weight: 2);
    final book = _m('book', ModuleValueType.book);
    final hidden = _m('hidden', ModuleValueType.score, max: 5, reports: false);
    final modules = [att, bed, book, hidden];

    test('ağırlıklı ortalama; kitap ve rapora dahil olmayanlar hariç', () {
      final cells = {
        'att': _c('a', 'att', 10, 90),
        'bed': _c('a', 'bed', 10, 60),
        'book': _c('a', 'book', 3, null),
        'hidden': _c('a', 'hidden', 10, 0),
      };
      // (90*1 + 60*2) / 3 = 70
      expect(generalScore(cells, modules), 70);
    });

    test('verisi olmayan modül hesaba girmez', () {
      expect(generalScore({'att': _c('a', 'att', 4, 75)}, modules), 75);
      expect(generalScore(null, modules), isNull);
      expect(generalScore({'book': _c('a', 'book', 2, null)}, modules), isNull);
    });
  });

  group('sıralama', () {
    final bed = _m('bed', ModuleValueType.score, max: 5);

    test('az kaydı olan öğrenci sıralamaya girmez', () {
      expect(minCountFor([10, 8, 2]), 5);
      expect(minCountFor([1, 1]), 1);
      expect(minCountFor(const []), 1);

      final report = groupReport([
        _c('a', 'bed', 10, 80),
        _c('b', 'bed', 1, 100), // tek kayıtla %100 -> sıralamaya alınmaz
        _c('c', 'bed', 9, 60),
      ]);
      final r = rankStudents(students: [_s('a'), _s('b'), _s('c')], report: report, modules: [bed], module: bed);
      expect(r.ranked.map((e) => e.item.student.id), ['a', 'c']);
      expect(r.excluded, 1);
      expect(r.minCount, 5);
    });

    test('kitapta eşik yok, kitap sayısına göre', () {
      final book = _m('book', ModuleValueType.book);
      final report = groupReport([_c('a', 'book', 1, null), _c('b', 'book', 4, null)]);
      final r = rankStudents(students: [_s('a'), _s('b')], report: report, modules: [book], module: book);
      expect(r.ranked.map((e) => (e.item.student.id, e.item.value)), [('b', 4.0), ('a', 1.0)]);
      expect(r.excluded, 0);
    });
  });

  test('gösterim', () {
    expect(formatPercent(75.4), '%75');
    expect(formatPercent(7.46), '%7,5');
    expect(formatPercent(null), '-');
    final att = _m('att', ModuleValueType.attendance);
    expect(cellDetail(att, _c('a', 'att', 20, 90, raw: 2, extra: 3)), '20 yoklama · 2 yok · 3 izinli');
    expect(cellDetail(_m('bed', ModuleValueType.score, max: 5), _c('a', 'bed', 6, 90, raw: 4.5)), '6 gün · ort. 4,5 / 5');
    expect(cellDetail(att, null), 'Veri yok');
  });
}
