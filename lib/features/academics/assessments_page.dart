import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/session.dart';
import '../../data/academics_repository.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../share/share_table.dart';
import 'academic_widgets.dart';
import 'ranking.dart';

/// Testler ve deneme sınavları listesi
class AssessmentsPage extends ConsumerStatefulWidget {
  const AssessmentsPage({super.key, required this.kind});

  final AssessmentKind kind;

  @override
  ConsumerState<AssessmentsPage> createState() => _AssessmentsPageState();
}

class _AssessmentsPageState extends ConsumerState<AssessmentsPage> {
  String? _group;

  AssessmentKind get kind => widget.kind;

  Future<void> _create() async {
    if (kind == AssessmentKind.trial) {
      context.push('/trials/new');
      return;
    }
    final r = await showHeaderDialog(context, mode: HeaderMode.test, groupId: _group);
    if (r == null || !mounted) return;
    final subjects = ref.read(subjectsProvider).value ?? const <Subject>[];
    String? id;
    final ok = await runAction(context, () async {
      id = await AcademicsRepo.createAssessment(
        kind: AssessmentKind.test,
        groupId: r.groupId,
        subjectId: r.subjectId,
        topicId: r.topicId,
        title: r.title,
        heldOn: r.heldOn,
        sections: [
          (name: subjectLabel(subjects, r.subjectId), subjectId: r.subjectId, questionCount: r.questionCount!),
        ],
      );
    });
    ref.invalidate(assessmentsProvider(kind));
    if (ok && mounted) context.push('/tests/$id');
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(myStudyGroupsProvider);
    final items = ref.watch(assessmentsProvider(kind));
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];

    return Scaffold(
      appBar: AppBar(title: Text(kind.pluralLabel)),
      floatingActionButton: (groupsAsync.value?.isEmpty ?? true)
          ? null
          : FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: Text('${kind.label} ekle')),
      body: AsyncView(
        value: groupsAsync,
        builder: (groups) {
          if (groups.isEmpty) return const NoStudyGroup();
          final names = {for (final g in groups) g.id: g.name};
          return Column(
            children: [
              GroupFilter(groups: groups, selected: _group, onChanged: (g) => setState(() => _group = g)),
              Expanded(
                child: AsyncView(
                  value: items,
                  onRetry: () => ref.invalidate(assessmentsProvider(kind)),
                  builder: (all) {
                    final list = all.where((a) => names.containsKey(a.groupId) && (_group == null || a.groupId == _group)).toList();
                    if (list.isEmpty) {
                      return EmptyState(
                        icon: kind == AssessmentKind.test ? Icons.quiz_outlined : Icons.assignment_outlined,
                        title: 'Henüz ${kind.label.toLowerCase()} girilmemiş',
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () async => ref.invalidate(assessmentsProvider(kind)),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final a = list[i];
                          final label = kind == AssessmentKind.test
                              ? subjectLabel(subjects, a.subjectId, a.topicId)
                              : a.sections.map((s) => s.name).join(', ');
                          final participants = a.sections.isEmpty ? 0 : (a.resultCount / a.sections.length).ceil();
                          return ContentWidth(
                            child: AcademicCard(
                              date: a.heldOn,
                              title: a.title ?? label,
                              subtitle: [
                                if (a.title != null) label,
                                names[a.groupId]!,
                                '${a.totalQuestions} soru',
                                participants == 0 ? 'Sonuç girilmedi' : '$participants öğrenci',
                              ].join(' · '),
                              onTap: () => context.push('${kind.routeBase}/${a.id}'),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

typedef AnswerInput = ({String correct, String wrong});

class AssessmentDetailPage extends ConsumerStatefulWidget {
  const AssessmentDetailPage({super.key, required this.kind, required this.assessmentId});

  final AssessmentKind kind;
  final String assessmentId;

  @override
  ConsumerState<AssessmentDetailPage> createState() => _AssessmentDetailPageState();
}

class _AssessmentDetailPageState extends ConsumerState<AssessmentDetailPage> {
  int _section = 0;

  /// bölüm id -> öğrenci id -> girilen değerler
  final Map<String, Map<String, AnswerInput>> _edits = {};
  bool _saving = false;

  int get _editCount => _edits.values.fold(0, (a, m) => a + m.length);

  Future<void> _save(Assessment a, Map<String, Map<String, AssessmentResult>> saved) async {
    final changes = <String, Map<String, ({int correct, int wrong})?>>{};
    for (final sec in a.sections) {
      final edits = _edits[sec.id];
      if (edits == null) continue;
      for (final e in edits.entries) {
        final parsed = parseAnswer(e.value, sec.questionCount);
        if (parsed is InvalidAnswer) {
          showMessage(context, '${sec.name}: doğru + yanlış soru sayısını (${sec.questionCount}) geçemez', error: true);
          return;
        }
        final value = parsed as ({int correct, int wrong})?;
        final old = saved[sec.id]?[e.key];
        final same = value == null ? old == null : (old != null && old.correct == value.correct && old.wrong == value.wrong);
        if (!same) changes.putIfAbsent(sec.id, () => {})[e.key] = value;
      }
    }
    if (changes.isEmpty) {
      setState(_edits.clear);
      return;
    }
    setState(() => _saving = true);
    final ok = await runAction(context, () async {
      for (final e in changes.entries) {
        await AcademicsRepo.saveAssessmentResults(e.key, e.value);
      }
    }, success: 'Sonuçlar kaydedildi');
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _edits.clear();
    });
    ref.invalidate(assessmentResultsProvider(a.id));
    ref.invalidate(assessmentsProvider(widget.kind));
  }

  Future<void> _menu(String action, Assessment a, String title) async {
    switch (action) {
      case 'edit':
        if (widget.kind == AssessmentKind.test) {
          final r = await showHeaderDialog(
            context,
            mode: HeaderMode.test,
            editing: true,
            groupId: a.groupId,
            subjectId: a.subjectId,
            topicId: a.topicId,
            title: a.title,
            heldOn: a.heldOn,
            questionCount: a.sections.first.questionCount,
          );
          if (r == null || !mounted) return;
          await runAction(context, () async {
            await AcademicsRepo.updateAssessment(a.id, title: r.title, heldOn: r.heldOn, topicId: r.topicId);
            if (r.questionCount != a.sections.first.questionCount) {
              await AcademicsRepo.updateSectionQuestionCount(a.sections.first.id, r.questionCount!);
            }
          });
        } else {
          final r = await _showTrialEditDialog(context, a);
          if (r == null || !mounted) return;
          await runAction(context, () => AcademicsRepo.updateAssessment(a.id, title: r.title, heldOn: r.heldOn));
        }
        ref.invalidate(assessmentsProvider(widget.kind));
      case 'delete':
        final yes = await confirm(context,
            title: '${widget.kind.label} sil', message: '"$title" ve girilen tüm sonuçlar silinecek.', confirmLabel: 'Sil', destructive: true);
        if (!yes || !mounted) return;
        final ok = await runAction(context, () => AcademicsRepo.deleteAssessment(a.id), success: 'Silindi');
        ref.invalidate(assessmentsProvider(widget.kind));
        if (ok && mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(assessmentsProvider(widget.kind));
    final results = ref.watch(assessmentResultsProvider(widget.assessmentId));
    final students = ref.watch(studentsProvider);
    final memberships = ref.watch(membershipsProvider);
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    final groups = ref.watch(groupsProvider).value ?? const <Group>[];

    final a = list.value?.where((x) => x.id == widget.assessmentId).firstOrNull;
    if (a == null) {
      return Scaffold(
        appBar: AppBar(),
        body: list.isLoading ? const Center(child: CircularProgressIndicator()) : const EmptyState(icon: Icons.search_off, title: 'Kayıt bulunamadı'),
      );
    }
    final isTest = widget.kind == AssessmentKind.test;
    final subject = isTest ? subjectLabel(subjects, a.subjectId, a.topicId) : null;
    final title = a.title ?? subject ?? 'Deneme';
    final groupName = groups.where((g) => g.id == a.groupId).firstOrNull?.name ?? '';
    final header = [groupName, formatDay(a.heldOn), if (a.title != null && subject != null) subject, '${a.totalQuestions} soru'].join(' · ');

    return DefaultTabController(
      length: 2,
      initialIndex: a.resultCount == 0 ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) => _menu(v, a, title),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                PopupMenuItem(value: 'delete', child: Text('Sil')),
              ],
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Sıralama'), Tab(text: 'Sonuç girişi')]),
        ),
        body: Builder(builder: (context) {
          if (!results.hasValue || !students.hasValue || !memberships.hasValue) {
            final err = results.error ?? students.error ?? memberships.error;
            return err != null ? ErrorView(message: err.toString()) : const Center(child: CircularProgressIndicator());
          }
          final saved = <String, Map<String, AssessmentResult>>{};
          for (final r in results.value!) {
            saved.putIfAbsent(r.sectionId, () => {})[r.studentId] = r;
          }
          final withResults = results.value!.map((r) => r.studentId).toSet();
          final roster = rosterWithResults(students.value!, memberships.value!, a.groupId, withResults);
          return TabBarView(
            children: [
              _Ranking(assessment: a, title: title, header: header, roster: roster, saved: saved),
              _entry(a, roster, saved),
            ],
          );
        }),
      ),
    );
  }

  Widget _entry(Assessment a, List<Student> roster, Map<String, Map<String, AssessmentResult>> saved) {
    if (roster.isEmpty) return const EmptyState(icon: Icons.groups_outlined, title: 'Grupta öğrenci yok');
    if (a.sections.isEmpty) return const EmptyState(icon: Icons.error_outline, title: 'Bölüm tanımlı değil');
    final sec = a.sections[_section.clamp(0, a.sections.length - 1)];
    final edits = _edits[sec.id] ?? const {};

    return Scaffold(
      floatingActionButton: _editCount == 0
          ? null
          : FloatingActionButton.extended(
              onPressed: _saving ? null : () => _save(a, saved),
              icon: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text('Kaydet ($_editCount)'),
            ),
      body: Column(
        children: [
          if (a.sections.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  for (var i = 0; i < a.sections.length; i++) ...[
                    ChoiceChip(
                      label: Text('${a.sections[i].name} (${a.sections[i].questionCount})'),
                      selected: i == _section,
                      onSelected: (_) => setState(() => _section = i),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('${sec.name}: ${sec.questionCount} soru · Boş otomatik hesaplanır · Net = D − Y/3',
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: roster.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, i) {
                final s = roster[i];
                final old = saved[sec.id]?[s.id];
                final initial = (correct: old?.correct.toString() ?? '', wrong: old?.wrong.toString() ?? '');
                final cur = edits[s.id] ?? initial;
                final parsed = parseAnswer(cur, sec.questionCount);
                final invalid = parsed is InvalidAnswer;
                final value = invalid ? null : parsed as ({int correct, int wrong})?;
                final info = value == null
                    ? (invalid ? 'Fazla cevap' : '')
                    : 'B ${sec.questionCount - value.correct - value.wrong} · Net ${formatNumber(netScore(value.correct, value.wrong))}';

                void update({String? correct, String? wrong}) => setState(() {
                      _edits.putIfAbsent(sec.id, () => {})[s.id] = (correct: correct ?? cur.correct, wrong: wrong ?? cur.wrong);
                    });

                return ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.fullName, overflow: TextOverflow.ellipsis),
                              if (info.isNotEmpty)
                                Text(info,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: invalid ? Theme.of(context).colorScheme.error : null,
                                        )),
                            ],
                          ),
                        ),
                        NumberBox(
                          key: ValueKey('${sec.id}-${s.id}-d'),
                          initial: initial.correct,
                          label: 'D',
                          error: invalid,
                          onChanged: (v) => update(correct: v),
                        ),
                        const SizedBox(width: 8),
                        NumberBox(
                          key: ValueKey('${sec.id}-${s.id}-y'),
                          initial: initial.wrong,
                          label: 'Y',
                          error: invalid,
                          onChanged: (v) => update(wrong: v),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class InvalidAnswer {
  const InvalidAnswer();
}

/// Boş giriş -> null (sonuç yok), geçerli -> (doğru, yanlış), soru sayısını aşıyorsa -> InvalidAnswer.
/// Sadece biri girildiyse diğeri 0 kabul edilir.
Object? parseAnswer(AnswerInput a, int questionCount) {
  final c = a.correct.trim(), w = a.wrong.trim();
  if (c.isEmpty && w.isEmpty) return null;
  final correct = int.tryParse(c.isEmpty ? '0' : c);
  final wrong = int.tryParse(w.isEmpty ? '0' : w);
  if (correct == null || wrong == null || correct + wrong > questionCount) return const InvalidAnswer();
  return (correct: correct, wrong: wrong);
}

class _Ranking extends StatelessWidget {
  const _Ranking({required this.assessment, required this.title, required this.header, required this.roster, required this.saved});

  final Assessment assessment;
  final String title;
  final String header;
  final List<Student> roster;
  final Map<String, Map<String, AssessmentResult>> saved;

  @override
  Widget build(BuildContext context) {
    final a = assessment;
    final isTest = a.kind == AssessmentKind.test;
    final byId = {for (final s in roster) s.id: s};
    final participants = {for (final m in saved.values) ...m.keys}.where(byId.containsKey).toList();
    if (participants.isEmpty) {
      return const EmptyState(icon: Icons.leaderboard_outlined, title: 'Henüz sonuç girilmedi', message: '"Sonuç girişi" sekmesinden doğru/yanlış sayılarını girin.');
    }

    double totalNet(String id) => a.sections.fold(0.0, (t, s) => t + (saved[s.id]?[id]?.net ?? 0));
    final ranked = rankBy(participants, totalNet, tieBreak: (id) => byId[id]!.fullName);
    final stats = Stats.of(participants.map(totalNet));

    List<String> cellsFor(String id) {
      if (isTest) {
        final r = saved[a.sections.first.id]![id]!;
        return ['${r.correct}', '${r.wrong}', '${a.sections.first.questionCount - r.correct - r.wrong}', formatNumber(r.net)];
      }
      return [
        for (final s in a.sections) saved[s.id]?[id] == null ? '-' : formatNumber(saved[s.id]![id]!.net),
        formatNumber(totalNet(id)),
      ];
    }

    final columns = ['Sıra', 'Öğrenci', if (isTest) ...['D', 'Y', 'B', 'Net'] else ...[for (final s in a.sections) s.name, 'Toplam']];

    ShareTable table() => ShareTable(
          title: title,
          subtitle: header,
          columns: columns,
          rows: [for (final r in ranked) ShareRow(studentId: r.item, cells: ['${r.rank}', byId[r.item]!.fullName, ...cellsFor(r.item)])],
          footer: 'Ortalama net ${formatNumber(stats.average!)} · ${stats.count} öğrenci · 3 yanlış 1 doğruyu götürür',
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(header, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              StatsBar(items: [
                ('Katılım', '${stats.count}/${roster.length}'),
                ('Ort. net', formatNumber(stats.average!)),
                ('En yüksek', formatNumber(stats.max!)),
                ('En düşük', formatNumber(stats.min!)),
              ]),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => openSharePreview(context, table()),
                icon: const Icon(Icons.share),
                label: const Text('Veliye paylaş'),
              ),
              const SizedBox(height: 12),
              Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: MediaQuery.sizeOf(context).width - 32),
                    child: DataTable(
                      columnSpacing: 16,
                      horizontalMargin: 12,
                      columns: [
                        for (var i = 0; i < columns.length; i++) DataColumn(label: Text(columns[i]), numeric: i >= 2),
                      ],
                      rows: [
                        for (final r in ranked)
                          DataRow(cells: [
                            DataCell(RankBadge(r.rank)),
                            DataCell(Text(byId[r.item]!.fullName)),
                            for (final (i, c) in cellsFor(r.item).indexed)
                              DataCell(Text(c, style: i == cellsFor(r.item).length - 1 ? const TextStyle(fontWeight: FontWeight.w700) : null)),
                          ]),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<({String? title, DateTime heldOn})?> _showTrialEditDialog(BuildContext context, Assessment a) {
  final title = TextEditingController(text: a.title);
  var date = a.heldOn;
  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Denemeyi düzenle'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Başlık')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(formatDay(date)),
                onTap: () async {
                  final today = session.ctx.today;
                  final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(today.year - 2), lastDate: today);
                  if (picked != null) setState(() => date = picked);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, (title: title.text, heldOn: date)), child: const Text('Kaydet')),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------

/// Hazır deneme şablonları (bölüm adı, soru sayısı)
const trialPresets = <String, List<(String, int)>>{
  'TYT': [('Türkçe', 40), ('Sosyal Bilimler', 20), ('Temel Matematik', 40), ('Fen Bilimleri', 20)],
  'AYT Sayısal': [('Matematik', 40), ('Fizik', 14), ('Kimya', 13), ('Biyoloji', 13)],
  'AYT Eşit Ağırlık': [('Matematik', 40), ('Edebiyat', 24), ('Tarih-1', 10), ('Coğrafya-1', 6)],
  'AYT Sözel': [('Edebiyat', 24), ('Tarih-1', 10), ('Coğrafya-1', 6), ('Tarih-2', 11), ('Coğrafya-2', 11), ('Felsefe Grubu', 12), ('Din Kültürü', 6)],
  'LGS': [('Türkçe', 20), ('Matematik', 20), ('Fen Bilimleri', 20), ('İnkılap Tarihi', 10), ('Din Kültürü', 10), ('İngilizce', 10)],
};

class TrialFormPage extends ConsumerStatefulWidget {
  const TrialFormPage({super.key});

  @override
  ConsumerState<TrialFormPage> createState() => _TrialFormPageState();
}

class _SectionDraft {
  _SectionDraft(String name, int count)
      : name = TextEditingController(text: name),
        count = TextEditingController(text: count == 0 ? '' : '$count');

  final TextEditingController name;
  final TextEditingController count;
}

class _TrialFormPageState extends ConsumerState<TrialFormPage> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  String? _group;
  late DateTime _date = session.ctx.today;
  final List<_SectionDraft> _sections = [];

  void _applyPreset(String name) {
    setState(() {
      _sections
        ..clear()
        ..addAll([for (final (n, c) in trialPresets[name]!) _SectionDraft(n, c)]);
      if (_title.text.trim().isEmpty) _title.text = '$name Denemesi';
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_sections.isEmpty) {
      showMessage(context, 'En az bir bölüm ekleyin', error: true);
      return;
    }
    final subjects = ref.read(subjectsProvider).value ?? const <Subject>[];
    String? subjectFor(String name) =>
        subjects.where((s) => s.name.toLowerCase() == name.trim().toLowerCase()).firstOrNull?.id;
    String? id;
    final ok = await runAction(context, () async {
      id = await AcademicsRepo.createAssessment(
        kind: AssessmentKind.trial,
        groupId: _group!,
        title: _title.text,
        heldOn: _date,
        sections: [
          for (final s in _sections)
            (name: s.name.text, subjectId: subjectFor(s.name.text), questionCount: int.parse(s.count.text)),
        ],
      );
    });
    ref.invalidate(assessmentsProvider(AssessmentKind.trial));
    if (ok && mounted) context.pushReplacement('/trials/$id');
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(myStudyGroupsProvider).value ?? const <Group>[];
    _group ??= groups.length == 1 ? groups.first.id : null;
    final total = _sections.fold(0, (a, s) => a + (int.tryParse(s.count.text) ?? 0));

    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Deneme Sınavı')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ContentWidth(
          maxWidth: 640,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _group,
                  decoration: const InputDecoration(labelText: 'Etüt grubu'),
                  validator: (v) => v == null ? 'Grup seçin' : null,
                  items: [for (final g in groups) DropdownMenuItem(value: g.id, child: Text(g.name))],
                  onChanged: (v) => setState(() => _group = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _title,
                  validator: requiredValidator,
                  decoration: const InputDecoration(labelText: 'Başlık', hintText: 'örn. TYT Deneme 3'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: Text(formatDay(_date)),
                  subtitle: const Text('Sınav tarihi'),
                  onTap: () async {
                    final today = session.ctx.today;
                    final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(today.year - 2), lastDate: today);
                    if (picked != null) setState(() => _date = picked);
                  },
                ),
                const SizedBox(height: 8),
                Text('Şablon', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final p in trialPresets.keys) ActionChip(label: Text(p), onPressed: () => _applyPreset(p))],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Bölümler (toplam $total soru)', style: Theme.of(context).textTheme.titleSmall),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => setState(() => _sections.add(_SectionDraft('', 0))),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Bölüm ekle'),
                    ),
                  ],
                ),
                for (var i = 0; i < _sections.length; i++)
                  Padding(
                    key: ObjectKey(_sections[i]),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _sections[i].name,
                            validator: requiredValidator,
                            decoration: const InputDecoration(labelText: 'Bölüm / ders', isDense: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 90,
                          child: TextFormField(
                            controller: _sections[i].count,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            onChanged: (_) => setState(() {}),
                            validator: (v) {
                              final n = int.tryParse(v ?? '');
                              return n == null || n < 1 || n > 500 ? '1-500' : null;
                            },
                            decoration: const InputDecoration(labelText: 'Soru', isDense: true),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _sections.removeAt(i)),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ],
                    ),
                  ),
                if (_sections.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Bir şablon seçin veya bölüm ekleyin.'),
                  ),
                const SizedBox(height: 12),
                Text('Bölüm adı tanımlı bir dersle aynıysa sonuçlar o derse bağlanır. '
                    'Bölümler oluşturulduktan sonra değiştirilemez.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                BusyButton(onPressed: _save, label: 'Oluştur', icon: Icons.check),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
