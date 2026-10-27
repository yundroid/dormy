import '../../core/formatters.dart';
import '../../models/models.dart';
import '../academics/ranking.dart';

/// student_report RPC satırı
class ReportCell {
  const ReportCell({required this.studentId, required this.moduleId, required this.count, this.percent, this.raw, this.extra});

  final String studentId;
  final String moduleId;
  final int count;
  final double? percent;
  final double? raw;
  final double? extra;

  factory ReportCell.fromJson(Map<String, dynamic> j) => ReportCell(
        studentId: j['student_id'] as String,
        moduleId: j['module_id'] as String,
        count: j['data_count'] as int,
        percent: (j['percent'] as num?)?.toDouble(),
        raw: (j['raw_value'] as num?)?.toDouble(),
        extra: (j['extra'] as num?)?.toDouble(),
      );
}

/// öğrenci id -> modül id -> hücre
typedef StudentReport = Map<String, Map<String, ReportCell>>;

StudentReport groupReport(Iterable<ReportCell> cells) {
  final out = <String, Map<String, ReportCell>>{};
  for (final c in cells) {
    out.putIfAbsent(c.studentId, () => {})[c.moduleId] = c;
  }
  return out;
}

typedef DateRange = ({DateTime from, DateTime to});

enum RangePreset {
  thisWeek('Bu hafta'),
  lastWeek('Geçen hafta'),
  thisMonth('Bu ay'),
  lastMonth('Geçen ay'),
  last30('Son 30 gün'),
  custom('Özel');

  const RangePreset(this.label);
  final String label;
}

/// Hafta pazartesi başlar. Bitiş bugünü geçmez.
DateRange rangeFor(RangePreset p, DateTime today, {DateRange? custom}) {
  final t = dateOnly(today);
  final monday = t.subtract(Duration(days: t.weekday - 1));
  return switch (p) {
    RangePreset.thisWeek => (from: monday, to: t),
    RangePreset.lastWeek => (from: monday.subtract(const Duration(days: 7)), to: monday.subtract(const Duration(days: 1))),
    RangePreset.thisMonth => (from: DateTime(t.year, t.month), to: t),
    RangePreset.lastMonth => (from: DateTime(t.year, t.month - 1), to: DateTime(t.year, t.month, 0)),
    RangePreset.last30 => (from: t.subtract(const Duration(days: 29)), to: t),
    RangePreset.custom => custom ?? (from: monday, to: t),
  };
}

String rangeLabel(DateRange r) =>
    r.from == r.to ? formatDay(r.from) : '${formatDay(r.from)} – ${formatDay(r.to)}';

/// Yüzdesi olan ve rapora dahil modüller (kitap gibi sayısal modüller hariç)
bool isPercentModule(DormModule m) => m.valueType != ModuleValueType.book;

/// Modül ağırlıklarıyla genel başarı yüzdesi. Verisi olmayan modüller hesaba girmez.
double? generalScore(Map<String, ReportCell>? cells, List<DormModule> modules) {
  if (cells == null) return null;
  var sum = 0.0, weight = 0.0;
  for (final m in modules) {
    if (!m.includeInReports || !isPercentModule(m) || m.weight <= 0) continue;
    final p = cells[m.id]?.percent;
    if (p == null) continue;
    sum += p * m.weight;
    weight += m.weight;
  }
  return weight == 0 ? null : sum / weight;
}

/// Türkçe yüzde gösterimi: "%75", "%7,5"
String formatPercent(double? p) => p == null ? '-' : '%${formatNumber(p >= 10 ? p.round() : (p * 10).round() / 10)}';

/// Modül hücresinin açıklaması: "2 yok · 1 izinli", "Ort. 4,5 / 5" ...
String cellDetail(DormModule m, ReportCell? c) {
  if (c == null || c.count == 0) return 'Veri yok';
  return switch (m.valueType) {
    ModuleValueType.attendance => [
        '${c.count} yoklama',
        '${formatNumber(c.raw ?? 0)} yok',
        if ((c.extra ?? 0) > 0) '${formatNumber(c.extra!)} izinli',
      ].join(' · '),
    ModuleValueType.score => '${c.count} gün · ort. ${formatNumber(c.raw ?? 0)} / ${m.maxValue}',
    ModuleValueType.yesNo => '${c.count} kontrol',
    ModuleValueType.exam => '${c.count} yazılı · ort. ${formatNumber(c.raw ?? 0)}',
    ModuleValueType.test => '${c.count} test · ort. net ${formatNumber(c.raw ?? 0)}',
    ModuleValueType.trialExam => '${c.count} deneme · ort. net ${formatNumber(c.raw ?? 0)}',
    ModuleValueType.book => '${c.count} kitap · ${formatNumber(c.extra ?? 0)} sayfa',
  };
}

/// Sıralamada kullanılan değer: yüzde, kitapta bitirilen kitap sayısı.
double? rankValue(DormModule m, ReportCell? c) {
  if (c == null) return null;
  return m.valueType == ModuleValueType.book ? c.count.toDouble() : c.percent;
}

/// Az verisi olan öğrencinin sıralamada üste çıkmaması için:
/// kayıt sayısı, en çok kaydı olan öğrencinin yarısından az olanlar sıralamaya girmez.
int minCountFor(Iterable<int> counts) {
  final max = counts.fold(0, (a, b) => a > b ? a : b);
  return max <= 1 ? 1 : (max / 2).ceil();
}

class RankEntry {
  const RankEntry({required this.student, required this.value, required this.count});

  final Student student;
  final double value;
  final int count;
}

/// [module] null ise genel başarı sıralaması.
({List<Ranked<RankEntry>> ranked, int minCount, int excluded}) rankStudents({
  required List<Student> students,
  required StudentReport report,
  required List<DormModule> modules,
  DormModule? module,
}) {
  final entries = <RankEntry>[];
  for (final s in students) {
    final cells = report[s.id];
    if (module == null) {
      final g = generalScore(cells, modules);
      final count = cells?.values.fold<int>(0, (a, c) => a + c.count) ?? 0;
      if (g != null) entries.add(RankEntry(student: s, value: g, count: count));
    } else {
      final c = cells?[module.id];
      final v = rankValue(module, c);
      if (v != null && c!.count > 0) entries.add(RankEntry(student: s, value: v, count: c.count));
    }
  }
  // Kitapta "az okuyan" da anlamlı bir sonuç olduğu için eşik uygulanmaz.
  final minCount = module?.valueType == ModuleValueType.book ? 1 : minCountFor(entries.map((e) => e.count));
  final eligible = entries.where((e) => e.count >= minCount).toList();
  return (
    ranked: rankBy(eligible, (e) => e.value, tieBreak: (e) => e.student.fullName),
    minCount: minCount,
    excluded: entries.length - eligible.length,
  );
}
