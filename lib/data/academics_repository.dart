import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatters.dart';
import '../core/session.dart';
import '../core/supabase.dart';
import '../models/models.dart';
import 'repository.dart';

List<Map<String, dynamic>> _rows(Object? data) => (data as List).cast<Map<String, dynamic>>();

String? _blank(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

/// Kullanıcının yönetebildiği etüt grupları (admin: hepsi, öğretmen: kendi grupları).
final myStudyGroupsProvider = FutureProvider<List<Group>>((ref) async {
  final groups = await ref.watch(groupsProvider.future);
  final study = groups.where((g) => g.kind == GroupKind.study && !g.isArchived);
  if (session.ctx.isAdmin) return study.toList();
  final teachers = await ref.watch(groupTeachersProvider.future);
  final me = currentUserId;
  return study.where((g) => teachers[g.id]?.contains(me) ?? false).toList();
});

// ---- Yazılılar
final examsProvider = FutureProvider<List<Exam>>((ref) async {
  final data = await db
      .from('exams')
      .select('id, group_id, subject_id, topic_id, title, held_on, created_by, exam_results(score)')
      .order('held_on', ascending: false)
      .order('created_at', ascending: false);
  return _rows(data).map(Exam.fromJson).toList();
});

final examResultsProvider = FutureProvider.autoDispose.family<List<ExamResult>, String>((ref, examId) async {
  final data = await db.from('exam_results').select('student_id, score').eq('exam_id', examId);
  return _rows(data).map(ExamResult.fromJson).toList();
});

// ---- Testler / denemeler
final assessmentsProvider = FutureProvider.family<List<Assessment>, AssessmentKind>((ref, kind) async {
  final data = await db
      .from('assessments')
      .select('id, kind, group_id, subject_id, topic_id, title, held_on, created_by, '
          'assessment_sections(id, name, subject_id, question_count, sort_order), assessment_results(count)')
      .eq('kind', kind.name)
      .order('held_on', ascending: false)
      .order('created_at', ascending: false);
  return _rows(data).map(Assessment.fromJson).toList();
});

final assessmentResultsProvider = FutureProvider.autoDispose.family<List<AssessmentResult>, String>((ref, id) async {
  final data = await db.from('assessment_results').select('section_id, student_id, correct, wrong').eq('assessment_id', id);
  return _rows(data).map(AssessmentResult.fromJson).toList();
});

// ---- Kitaplar
final booksProvider = FutureProvider<List<Book>>((ref) async {
  final data = await db.from('books').select('id, title, author, page_count, created_by').order('title');
  return _rows(data).map(Book.fromJson).toList();
});

final bookAssignmentsProvider = FutureProvider<List<BookAssignment>>((ref) async {
  final data = await db.from('book_assignments').select().order('updated_at', ascending: false);
  return _rows(data).map(BookAssignment.fromJson).toList();
});

class AcademicsRepo {
  static String get _tenantId => session.ctx.tenantId;

  // ---- Yazılılar
  static Future<String> saveExam({
    String? id,
    required String groupId,
    required String subjectId,
    String? topicId,
    String? title,
    required DateTime heldOn,
  }) async {
    final payload = {
      'tenant_id': _tenantId,
      'group_id': groupId,
      'subject_id': subjectId,
      'topic_id': topicId,
      'title': _blank(title),
      'held_on': isoDate(heldOn),
    };
    if (id == null) {
      final row = await db.from('exams').insert(payload).select('id').single();
      return row['id'] as String;
    }
    await db.from('exams').update(payload).eq('id', id);
    return id;
  }

  static Future<void> deleteExam(String id) => db.from('exams').delete().eq('id', id);

  /// [scores]: öğrenci -> not (null = sonucu sil)
  static Future<void> saveExamResults(String examId, Map<String, num?> scores) async {
    final upserts = [
      for (final e in scores.entries)
        if (e.value != null) {'exam_id': examId, 'student_id': e.key, 'score': e.value},
    ];
    final deletes = [for (final e in scores.entries) if (e.value == null) e.key];
    if (upserts.isNotEmpty) await db.from('exam_results').upsert(upserts, onConflict: 'exam_id,student_id');
    if (deletes.isNotEmpty) {
      await db.from('exam_results').delete().eq('exam_id', examId).inFilter('student_id', deletes);
    }
  }

  // ---- Testler / denemeler
  static Future<String> createAssessment({
    required AssessmentKind kind,
    required String groupId,
    String? subjectId,
    String? topicId,
    String? title,
    required DateTime heldOn,
    required List<({String name, String? subjectId, int questionCount})> sections,
  }) async {
    final row = await db
        .from('assessments')
        .insert({
          'tenant_id': _tenantId,
          'kind': kind.name,
          'group_id': groupId,
          'subject_id': subjectId,
          'topic_id': topicId,
          'title': _blank(title),
          'held_on': isoDate(heldOn),
        })
        .select('id')
        .single();
    final id = row['id'] as String;
    try {
      await db.from('assessment_sections').insert([
        for (var i = 0; i < sections.length; i++)
          {
            'tenant_id': _tenantId,
            'assessment_id': id,
            'name': sections[i].name.trim(),
            'subject_id': sections[i].subjectId,
            'question_count': sections[i].questionCount,
            'sort_order': i,
          },
      ]);
    } catch (_) {
      await db.from('assessments').delete().eq('id', id);
      rethrow;
    }
    return id;
  }

  static Future<void> updateAssessment(String id, {String? title, required DateTime heldOn, String? topicId}) =>
      db.from('assessments').update({'title': _blank(title), 'held_on': isoDate(heldOn), 'topic_id': topicId}).eq('id', id);

  static Future<void> updateSectionQuestionCount(String sectionId, int count) =>
      db.from('assessment_sections').update({'question_count': count}).eq('id', sectionId);

  static Future<void> deleteAssessment(String id) => db.from('assessments').delete().eq('id', id);

  /// [answers]: öğrenci -> (doğru, yanlış) (null = sonucu sil)
  static Future<void> saveAssessmentResults(String sectionId, Map<String, ({int correct, int wrong})?> answers) async {
    final upserts = [
      for (final e in answers.entries)
        if (e.value != null)
          {'section_id': sectionId, 'student_id': e.key, 'correct': e.value!.correct, 'wrong': e.value!.wrong},
    ];
    final deletes = [for (final e in answers.entries) if (e.value == null) e.key];
    if (upserts.isNotEmpty) await db.from('assessment_results').upsert(upserts, onConflict: 'section_id,student_id');
    if (deletes.isNotEmpty) {
      await db.from('assessment_results').delete().eq('section_id', sectionId).inFilter('student_id', deletes);
    }
  }

  // ---- Kitaplar
  static Future<String> saveBook({String? id, required String title, String? author, int? pageCount}) async {
    final payload = {'tenant_id': _tenantId, 'title': title.trim(), 'author': _blank(author), 'page_count': pageCount};
    if (id == null) {
      final row = await db.from('books').insert(payload).select('id').single();
      return row['id'] as String;
    }
    await db.from('books').update(payload).eq('id', id);
    return id;
  }

  static Future<void> deleteBook(String id) => db.from('books').delete().eq('id', id);

  static Future<void> assignBook(String bookId, Iterable<String> studentIds) => db.from('book_assignments').upsert(
        [for (final s in studentIds) {'tenant_id': _tenantId, 'book_id': bookId, 'student_id': s}],
        onConflict: 'book_id,student_id',
        ignoreDuplicates: true,
      );

  static Future<void> updateAssignment(String id, {required BookStatus status, required int pagesRead, String? note}) =>
      db.from('book_assignments').update({'status': status.name, 'pages_read': pagesRead, 'note': _blank(note)}).eq('id', id);

  static Future<void> deleteAssignment(String id) => db.from('book_assignments').delete().eq('id', id);
}
