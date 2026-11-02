import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/session.dart';
import '../core/supabase.dart';

/// Günlük programın bir satırı. Saatler gün başından itibaren dakika olarak tutulur.
class ScheduleItem {
  const ScheduleItem({
    required this.id,
    required this.start,
    required this.end,
    required this.title,
    required this.days,
    this.note,
  });

  final String id;

  /// 06:30 -> 390
  final int start;
  final int end;
  final String title;
  final String? note;

  /// 1 = Pazartesi ... 7 = Pazar
  final Set<int> days;

  factory ScheduleItem.fromJson(Map<String, dynamic> j) => ScheduleItem(
        id: j['id'] as String,
        start: parseTimeOfDay(j['starts_at'] as String),
        end: parseTimeOfDay(j['ends_at'] as String),
        title: j['title'] as String,
        note: j['note'] as String?,
        days: {for (final d in j['days'] as List) d as int},
      );
}

/// "06:30:00" -> 390
int parseTimeOfDay(String s) {
  final parts = s.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// 390 -> "06:30"
String formatMinutes(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

const weekdayShort = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
const weekdayLong = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];

/// "Her gün", "Hafta içi", "Hafta sonu" ya da "Pzt, Çar, Cum"
String daysLabel(Set<int> days) {
  if (days.length == 7) return 'Her gün';
  if (days.length == 5 && days.containsAll(const [1, 2, 3, 4, 5])) return 'Hafta içi';
  if (days.length == 2 && days.containsAll(const [6, 7])) return 'Hafta sonu';
  return [for (var d = 1; d <= 7; d++) if (days.contains(d)) weekdayShort[d - 1]].join(', ');
}

/// Seçilen günün programı, başlangıç saatine göre sıralı.
List<ScheduleItem> itemsForDay(List<ScheduleItem> all, int weekday) =>
    all.where((i) => i.days.contains(weekday)).toList()
      ..sort((a, b) => a.start != b.start ? a.start.compareTo(b.start) : a.end.compareTo(b.end));

enum ScheduleState { past, now, next, later }

/// Bugünün listesinde her satırın durumu: geçti / şimdi / sıradaki / sonra.
/// Aynı anda birden fazla etkinlik sürüyorsa hepsi "şimdi" olur; "sıradaki" en yakın başlayandır.
List<ScheduleState> statesFor(List<ScheduleItem> day, int nowMinutes) {
  final states = [
    for (final i in day)
      nowMinutes >= i.end
          ? ScheduleState.past
          : (nowMinutes >= i.start ? ScheduleState.now : ScheduleState.later),
  ];
  final nextIndex = states.indexOf(ScheduleState.later);
  if (nextIndex >= 0) states[nextIndex] = ScheduleState.next;
  return states;
}

final scheduleProvider = FutureProvider<List<ScheduleItem>>((ref) async {
  final data = await db.from('schedule_items').select().order('starts_at', ascending: true);
  return (data as List).cast<Map<String, dynamic>>().map(ScheduleItem.fromJson).toList();
});

class ScheduleRepo {
  static Future<void> save({
    String? id,
    required int start,
    required int end,
    required String title,
    String? note,
    required Set<int> days,
  }) async {
    final payload = {
      'tenant_id': session.ctx.tenantId,
      'starts_at': formatMinutes(start),
      'ends_at': formatMinutes(end),
      'title': title.trim(),
      'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
      'days': (days.toList()..sort()),
    };
    if (id == null) {
      await db.from('schedule_items').insert(payload);
    } else {
      await db.from('schedule_items').update(payload).eq('id', id);
    }
  }

  static Future<void> delete(String id) => db.from('schedule_items').delete().eq('id', id);
}
