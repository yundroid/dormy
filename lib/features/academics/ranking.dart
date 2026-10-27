import 'package:intl/intl.dart';

final _num = NumberFormat('#,##0.##', 'tr_TR');

/// Türkçe ondalık biçimi: 10.333 -> "10,33"
String formatNumber(num v) => _num.format(v);

class Ranked<T> {
  const Ranked(this.rank, this.item);

  final int rank;
  final T item;
}

/// Yüksekten düşüğe sıralar; eşit değerler aynı sırayı alır (1, 1, 3).
List<Ranked<T>> rankBy<T>(Iterable<T> items, num Function(T) value, {String Function(T)? tieBreak}) {
  final sorted = items.toList()
    ..sort((a, b) {
      final c = value(b).compareTo(value(a));
      if (c != 0 || tieBreak == null) return c;
      return tieBreak(a).compareTo(tieBreak(b));
    });
  final out = <Ranked<T>>[];
  for (var i = 0; i < sorted.length; i++) {
    final rank = i > 0 && value(sorted[i]) == value(sorted[i - 1]) ? out[i - 1].rank : i + 1;
    out.add(Ranked(rank, sorted[i]));
  }
  return out;
}

class Stats {
  const Stats({required this.count, this.average, this.max, this.min});

  final int count;
  final double? average;
  final num? max;
  final num? min;

  factory Stats.of(Iterable<num> values) {
    final list = <num>[...values];
    if (list.isEmpty) return const Stats(count: 0);
    final sum = list.fold<num>(0, (a, b) => a + b);
    return Stats(
      count: list.length,
      average: sum / list.length,
      max: list.reduce((a, b) => a > b ? a : b),
      min: list.reduce((a, b) => a < b ? a : b),
    );
  }
}

/// Paylaşımda isim gösterimi
enum NameMode {
  full('Tam isim'),
  initials('Baş harfler'),
  single('Tek öğrenci');

  const NameMode(this.label);
  final String label;
}

/// "Ahmet Can Yılmaz" -> "A. C. Y."
String initialsOf(String fullName) => fullName
    .trim()
    .split(RegExp(r'\s+'))
    .where((p) => p.isNotEmpty)
    .map((p) => '${trUpper(String.fromCharCode(p.runes.first))}.')
    .join(' ');

/// [single] modunda sadece [highlightId] öğrencisinin adı açık kalır.
String maskName(String fullName, NameMode mode, {String? studentId, String? highlightId}) => switch (mode) {
      NameMode.full => fullName,
      NameMode.initials => initialsOf(fullName),
      NameMode.single => studentId != null && studentId == highlightId ? fullName : '• • •',
    };

/// Türkçe büyük harf (i -> İ, ı -> I)
String trUpper(String s) => s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
