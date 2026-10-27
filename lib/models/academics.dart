import '../core/formatters.dart';

DateTime? _ts(Object? v) => v == null ? null : DateTime.parse(v as String);
DateTime? _date(Object? v) => v == null ? null : parseDate(v as String);

/// Yazılı sınav
class Exam {
  Exam({
    required this.id,
    required this.groupId,
    required this.subjectId,
    required this.heldOn,
    required this.scores,
    this.topicId,
    this.title,
    this.createdBy,
  });

  final String id;
  final String groupId;
  final String subjectId;
  final String? topicId;
  final String? title;
  final DateTime heldOn;
  final String? createdBy;

  /// Listede özet göstermek için tüm notlar
  final List<num> scores;

  factory Exam.fromJson(Map<String, dynamic> j) => Exam(
        id: j['id'] as String,
        groupId: j['group_id'] as String,
        subjectId: j['subject_id'] as String,
        topicId: j['topic_id'] as String?,
        title: j['title'] as String?,
        heldOn: parseDate(j['held_on'] as String),
        createdBy: j['created_by'] as String?,
        scores: [for (final r in (j['exam_results'] as List? ?? const [])) (r as Map)['score'] as num],
      );
}

class ExamResult {
  ExamResult({required this.studentId, required this.score});

  final String studentId;
  final num score;

  factory ExamResult.fromJson(Map<String, dynamic> j) =>
      ExamResult(studentId: j['student_id'] as String, score: j['score'] as num);
}

enum AssessmentKind {
  test('Test', 'Testler'),
  trial('Deneme', 'Deneme Sınavları');

  const AssessmentKind(this.label, this.pluralLabel);
  final String label;
  final String pluralLabel;

  String get featureCode => this == test ? 'tests' : 'trial_exams';
  String get routeBase => this == test ? '/tests' : '/trials';
}

/// Test (tek bölüm) ya da deneme sınavı (çok bölüm)
class Assessment {
  Assessment({
    required this.id,
    required this.kind,
    required this.groupId,
    required this.heldOn,
    required this.sections,
    required this.resultCount,
    this.subjectId,
    this.topicId,
    this.title,
    this.createdBy,
  });

  final String id;
  final AssessmentKind kind;
  final String groupId;
  final String? subjectId;
  final String? topicId;
  final String? title;
  final DateTime heldOn;
  final String? createdBy;
  final List<AssessmentSection> sections;

  /// Girilmiş sonuç satırı sayısı (öğrenci × bölüm)
  final int resultCount;

  int get totalQuestions => sections.fold(0, (a, s) => a + s.questionCount);

  factory Assessment.fromJson(Map<String, dynamic> j) {
    final results = j['assessment_results'] as List?;
    return Assessment(
      id: j['id'] as String,
      kind: AssessmentKind.values.byName(j['kind'] as String),
      groupId: j['group_id'] as String,
      subjectId: j['subject_id'] as String?,
      topicId: j['topic_id'] as String?,
      title: j['title'] as String?,
      heldOn: parseDate(j['held_on'] as String),
      createdBy: j['created_by'] as String?,
      sections: [
        for (final s in (j['assessment_sections'] as List? ?? const [])) AssessmentSection.fromJson(s as Map<String, dynamic>),
      ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
      resultCount: results == null || results.isEmpty ? 0 : ((results.first as Map)['count'] as int? ?? 0),
    );
  }
}

class AssessmentSection {
  AssessmentSection({required this.id, required this.name, required this.questionCount, required this.sortOrder, this.subjectId});

  final String id;
  final String name;
  final String? subjectId;
  final int questionCount;
  final int sortOrder;

  factory AssessmentSection.fromJson(Map<String, dynamic> j) => AssessmentSection(
        id: j['id'] as String,
        name: j['name'] as String,
        subjectId: j['subject_id'] as String?,
        questionCount: j['question_count'] as int,
        sortOrder: j['sort_order'] as int? ?? 0,
      );
}

class AssessmentResult {
  AssessmentResult({required this.sectionId, required this.studentId, required this.correct, required this.wrong});

  final String sectionId;
  final String studentId;
  final int correct;
  final int wrong;

  double get net => netScore(correct, wrong);

  factory AssessmentResult.fromJson(Map<String, dynamic> j) => AssessmentResult(
        sectionId: j['section_id'] as String,
        studentId: j['student_id'] as String,
        correct: j['correct'] as int,
        wrong: j['wrong'] as int,
      );
}

/// 3 yanlış 1 doğruyu götürür.
double netScore(int correct, int wrong) => correct - wrong / 3;

enum BookStatus {
  assigned('Atandı'),
  reading('Okunuyor'),
  finished('Bitirdi'),
  dropped('Bıraktı');

  const BookStatus(this.label);
  final String label;
}

class Book {
  Book({required this.id, required this.title, this.author, this.pageCount, this.createdBy});

  final String id;
  final String title;
  final String? author;
  final int? pageCount;
  final String? createdBy;

  String get display => author == null ? title : '$title · $author';

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'] as String,
        title: j['title'] as String,
        author: j['author'] as String?,
        pageCount: j['page_count'] as int?,
        createdBy: j['created_by'] as String?,
      );
}

class BookAssignment {
  BookAssignment({
    required this.id,
    required this.bookId,
    required this.studentId,
    required this.status,
    required this.pagesRead,
    required this.assignedOn,
    this.startedOn,
    this.finishedOn,
    this.note,
    this.updatedAt,
  });

  final String id;
  final String bookId;
  final String studentId;
  final BookStatus status;
  final int pagesRead;
  final DateTime assignedOn;
  final DateTime? startedOn;
  final DateTime? finishedOn;
  final String? note;
  final DateTime? updatedAt;

  bool get isOpen => status == BookStatus.assigned || status == BookStatus.reading;

  factory BookAssignment.fromJson(Map<String, dynamic> j) => BookAssignment(
        id: j['id'] as String,
        bookId: j['book_id'] as String,
        studentId: j['student_id'] as String,
        status: BookStatus.values.byName(j['status'] as String),
        pagesRead: j['pages_read'] as int? ?? 0,
        assignedOn: parseDate(j['assigned_on'] as String),
        startedOn: _date(j['started_on']),
        finishedOn: _date(j['finished_on']),
        note: j['note'] as String?,
        updatedAt: _ts(j['updated_at']),
      );
}
