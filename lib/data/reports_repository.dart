import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatters.dart';
import '../core/supabase.dart';
import '../features/reports/report_logic.dart';

final reportProvider = FutureProvider.autoDispose.family<StudentReport, DateRange>((ref, range) async {
  final data = await db.rpc('student_report', params: {'p_from': isoDate(range.from), 'p_to': isoDate(range.to)});
  return groupReport((data as List).cast<Map<String, dynamic>>().map(ReportCell.fromJson));
});
