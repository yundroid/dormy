import '../../models/models.dart';

/// Her vakitte kaç öğrenci için giriş yapılmış.
List<int> sessionCounts(int sessionCount, List<Entry> entries) {
  final counts = List.filled(sessionCount, 0);
  for (final e in entries) {
    if (e.session < sessionCount) counts[e.session]++;
  }
  return counts;
}

/// Ekran açılınca seçilecek vakit: tamamlanmamış ilk vakit, hepsi tamamsa sonuncusu.
int firstIncompleteSession(int sessionCount, List<Entry> entries, int studentCount) {
  final counts = sessionCounts(sessionCount, entries);
  for (var i = 0; i < sessionCount; i++) {
    if (counts[i] < studentCount) return i;
  }
  return sessionCount - 1;
}

class ValueOption {
  const ValueOption(this.value, this.label);

  final Object value;
  final String label;
}

/// Toplu doldurma için önerilen değerler.
List<ValueOption> valueOptions(DormModule m) => switch (m.valueType) {
      ModuleValueType.attendance => [
          for (final c in AttendanceChoice.values) ValueOption(c.name, c.label),
        ],
      ModuleValueType.yesNo => const [ValueOption(1, 'Evet'), ValueOption(0, 'Hayır')],
      ModuleValueType.score => m.maxValue! - m.minValue! <= 9
          ? [for (var v = m.maxValue!; v >= m.minValue!; v--) ValueOption(v, '$v')]
          : [ValueOption(m.maxValue!, '${m.maxValue}')],
    };

class EntrySummary {
  const EntrySummary({required this.filled, this.attendance, this.average});

  final int filled;
  final Map<AttendanceChoice, int>? attendance;
  final double? average;
}

EntrySummary summarize(DormModule m, Iterable<Object?> values) {
  final filled = values.where((v) => v != null).toList();
  switch (m.valueType) {
    case ModuleValueType.attendance:
      final counts = <AttendanceChoice, int>{};
      for (final v in filled) {
        final c = AttendanceChoice.parse(v as String);
        counts[c] = (counts[c] ?? 0) + 1;
      }
      return EntrySummary(filled: filled.length, attendance: counts);
    case ModuleValueType.score:
    case ModuleValueType.yesNo:
      final nums = filled.whereType<num>().toList();
      final avg = nums.isEmpty ? null : nums.reduce((a, b) => a + b) / nums.length;
      return EntrySummary(filled: filled.length, average: m.valueType == ModuleValueType.score ? avg : null);
  }
}
