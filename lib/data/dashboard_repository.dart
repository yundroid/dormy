import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatters.dart';
import '../core/supabase.dart';

typedef SessionProgress = ({int session, int filled, int total});

class ModuleProgress {
  const ModuleProgress(this.sessions);

  final List<SessionProgress> sessions;

  int get total => sessions.isEmpty ? 0 : sessions.first.total;
  int get filled => sessions.fold(0, (a, s) => a + s.filled);
  int get sessionsDone => sessions.where((s) => s.total > 0 && s.filled >= s.total).length;
  bool get complete => total > 0 && sessionsDone == sessions.length;

  /// 0..1 arası doluluk
  double get ratio => total == 0 || sessions.isEmpty ? 0 : filled / (total * sessions.length);

  String get label {
    if (total == 0) return 'Listede öğrenci yok';
    if (sessions.length > 1) return 'Bugün $sessionsDone/${sessions.length} vakit';
    return 'Bugün $filled/$total';
  }
}

/// modül id -> bugünkü doluluk
final todayProgressProvider = FutureProvider.autoDispose<Map<String, ModuleProgress>>((ref) async {
  final data = (await db.rpc('today_progress') as List).cast<Map<String, dynamic>>();
  final grouped = <String, List<SessionProgress>>{};
  for (final r in data) {
    grouped.putIfAbsent(r['module_id'] as String, () => []).add(
          (session: r['session'] as int, filled: r['filled'] as int, total: r['total'] as int),
        );
  }
  return {
    for (final e in grouped.entries) e.key: ModuleProgress(e.value..sort((a, b) => a.session.compareTo(b.session))),
  };
});

typedef AbsenceAlert = ({String studentId, int absentCount, DateTime lastAbsent});

/// Son 7 günde en az 3 kez "yok" yazılan öğrenciler
final attendanceAlertsProvider = FutureProvider.autoDispose<List<AbsenceAlert>>((ref) async {
  final data = (await db.rpc('attendance_alerts') as List).cast<Map<String, dynamic>>();
  return [
    for (final r in data)
      (
        studentId: r['student_id'] as String,
        absentCount: r['absent_count'] as int,
        lastAbsent: parseDate(r['last_absent'] as String),
      ),
  ];
});
