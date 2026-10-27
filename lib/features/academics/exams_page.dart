import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../data/academics_repository.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../share/share_table.dart';
import 'academic_widgets.dart';
import 'ranking.dart';

class ExamsPage extends ConsumerStatefulWidget {
  const ExamsPage({super.key});

  @override
  ConsumerState<ExamsPage> createState() => _ExamsPageState();
}

class _ExamsPageState extends ConsumerState<ExamsPage> {
  String? _group;

  Future<void> _create() async {
    final r = await showHeaderDialog(context, mode: HeaderMode.exam, groupId: _group);
    if (r == null || !mounted) return;
    String? id;
    final ok = await runAction(context, () async {
      id = await AcademicsRepo.saveExam(
        groupId: r.groupId,
        subjectId: r.subjectId,
        topicId: r.topicId,
        title: r.title,
        heldOn: r.heldOn,
      );
    });
    ref.invalidate(examsProvider);
    if (ok && mounted) context.push('/exams/$id');
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(myStudyGroupsProvider);
    final exams = ref.watch(examsProvider);
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Yazılılar')),
      floatingActionButton: (groupsAsync.value?.isEmpty ?? true)
          ? null
          : FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Yazılı ekle')),
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
                  value: exams,
                  onRetry: () => ref.invalidate(examsProvider),
                  builder: (all) {
                    final list = all.where((e) => names.containsKey(e.groupId) && (_group == null || e.groupId == _group)).toList();
                    if (list.isEmpty) {
                      return const EmptyState(icon: Icons.edit_note, title: 'Henüz yazılı girilmemiş');
                    }
                    return RefreshIndicator(
                      onRefresh: () async => ref.invalidate(examsProvider),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final e = list[i];
                          final stats = Stats.of(e.scores);
                          return ContentWidth(
                            child: AcademicCard(
                              date: e.heldOn,
                              title: e.title ?? subjectLabel(subjects, e.subjectId, e.topicId),
                              subtitle: [
                                if (e.title != null) subjectLabel(subjects, e.subjectId, e.topicId),
                                names[e.groupId]!,
                                stats.count == 0 ? 'Not girilmedi' : '${stats.count} öğrenci · ort. ${formatNumber(stats.average!)}',
                              ].join(' · '),
                              onTap: () => context.push('/exams/${e.id}'),
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

class ExamDetailPage extends ConsumerStatefulWidget {
  const ExamDetailPage({super.key, required this.examId});

  final String examId;

  @override
  ConsumerState<ExamDetailPage> createState() => _ExamDetailPageState();
}

class _ExamDetailPageState extends ConsumerState<ExamDetailPage> {
  final Map<String, String> _edits = {};
  bool _saving = false;

  num? _parse(String s) {
    final t = s.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return num.tryParse(t);
  }

  bool _valid(String s) {
    if (s.trim().isEmpty) return true;
    final n = _parse(s);
    return n != null && n >= 0 && n <= 100;
  }

  Future<void> _save(Map<String, num> saved) async {
    if (_edits.values.any((v) => !_valid(v))) {
      showMessage(context, 'Notlar 0 ile 100 arasında olmalı', error: true);
      return;
    }
    final changes = <String, num?>{
      for (final e in _edits.entries)
        if (_parse(e.value) != saved[e.key]) e.key: _parse(e.value),
    };
    if (changes.isEmpty) {
      setState(_edits.clear);
      return;
    }
    setState(() => _saving = true);
    final ok = await runAction(context, () => AcademicsRepo.saveExamResults(widget.examId, changes), success: 'Notlar kaydedildi');
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _edits.clear();
    });
    ref.invalidate(examResultsProvider(widget.examId));
    ref.invalidate(examsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final exams = ref.watch(examsProvider);
    final results = ref.watch(examResultsProvider(widget.examId));
    final students = ref.watch(studentsProvider);
    final memberships = ref.watch(membershipsProvider);
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    final groups = ref.watch(groupsProvider).value ?? const <Group>[];

    final exam = exams.value?.where((e) => e.id == widget.examId).firstOrNull;
    if (exam == null) {
      return Scaffold(
        appBar: AppBar(),
        body: exams.isLoading ? const Center(child: CircularProgressIndicator()) : const EmptyState(icon: Icons.search_off, title: 'Yazılı bulunamadı'),
      );
    }
    final groupName = groups.where((g) => g.id == exam.groupId).firstOrNull?.name ?? '';
    final subject = subjectLabel(subjects, exam.subjectId, exam.topicId);
    final title = exam.title ?? subject;

    Future<void> menu(String a) async {
      switch (a) {
        case 'edit':
          final r = await showHeaderDialog(
            context,
            mode: HeaderMode.exam,
            editing: true,
            groupId: exam.groupId,
            subjectId: exam.subjectId,
            topicId: exam.topicId,
            title: exam.title,
            heldOn: exam.heldOn,
          );
          if (r == null || !context.mounted) return;
          await runAction(context, () => AcademicsRepo.saveExam(
                id: exam.id,
                groupId: exam.groupId,
                subjectId: exam.subjectId,
                topicId: r.topicId,
                title: r.title,
                heldOn: r.heldOn,
              ));
          ref.invalidate(examsProvider);
        case 'delete':
          final yes = await confirm(context,
              title: 'Yazılıyı sil', message: '"$title" ve girilen tüm notlar silinecek.', confirmLabel: 'Sil', destructive: true);
          if (!yes || !context.mounted) return;
          final ok = await runAction(context, () => AcademicsRepo.deleteExam(exam.id), success: 'Yazılı silindi');
          ref.invalidate(examsProvider);
          if (ok && context.mounted) context.pop();
      }
    }

    return DefaultTabController(
      length: 2,
      initialIndex: exam.scores.isEmpty ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            PopupMenuButton<String>(
              onSelected: menu,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                PopupMenuItem(value: 'delete', child: Text('Sil')),
              ],
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Sıralama'), Tab(text: 'Not girişi')]),
        ),
        body: Builder(builder: (context) {
          if (!results.hasValue || !students.hasValue || !memberships.hasValue) {
            final err = results.error ?? students.error ?? memberships.error;
            return err != null ? ErrorView(message: err.toString()) : const Center(child: CircularProgressIndicator());
          }
          final saved = {for (final r in results.value!) r.studentId: r.score};
          final roster = rosterWithResults(students.value!, memberships.value!, exam.groupId, saved.keys.toSet());
          final header = '$groupName · ${formatDay(exam.heldOn)}${exam.title != null ? ' · $subject' : ''}';
          return TabBarView(
            children: [
              _ExamRanking(title: title, header: header, roster: roster, saved: saved),
              _ExamEntry(
                roster: roster,
                saved: saved,
                edits: _edits,
                saving: _saving,
                valid: _valid,
                onChanged: (id, v) => setState(() => _edits[id] = v),
                onSave: () => _save(saved),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _ExamRanking extends StatelessWidget {
  const _ExamRanking({required this.title, required this.header, required this.roster, required this.saved});

  final String title;
  final String header;
  final List<Student> roster;
  final Map<String, num> saved;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final s in roster) s.id: s};
    final ranked = rankBy(saved.entries.where((e) => byId.containsKey(e.key)), (e) => e.value, tieBreak: (e) => byId[e.key]!.fullName);
    if (ranked.isEmpty) {
      return const EmptyState(icon: Icons.leaderboard_outlined, title: 'Henüz not girilmedi', message: '"Not girişi" sekmesinden notları girin.');
    }
    final stats = Stats.of(saved.values);
    final missing = roster.where((s) => !saved.containsKey(s.id)).toList();

    ShareTable table() => ShareTable(
          title: title,
          subtitle: header,
          columns: const ['Sıra', 'Öğrenci', 'Not'],
          rows: [
            for (final r in ranked)
              ShareRow(studentId: r.item.key, cells: ['${r.rank}', byId[r.item.key]!.fullName, formatNumber(r.item.value)]),
          ],
          footer: 'Ortalama ${formatNumber(stats.average!)} · ${stats.count} öğrenci',
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
              Row(
                children: [
                  Expanded(
                    child: StatsBar(items: [
                      ('Katılım', '${stats.count}/${roster.length}'),
                      ('Ortalama', formatNumber(stats.average!)),
                      ('En yüksek', formatNumber(stats.max!)),
                      ('En düşük', formatNumber(stats.min!)),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => openSharePreview(context, table()),
                icon: const Icon(Icons.share),
                label: const Text('Veliye paylaş'),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    for (final r in ranked)
                      ListTile(
                        leading: RankBadge(r.rank),
                        title: Text(byId[r.item.key]!.fullName),
                        trailing: Text(formatNumber(r.item.value), style: Theme.of(context).textTheme.titleMedium),
                      ),
                  ],
                ),
              ),
              if (missing.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Notu girilmeyenler: ${missing.map((s) => s.fullName).join(', ')}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ExamEntry extends StatelessWidget {
  const _ExamEntry({
    required this.roster,
    required this.saved,
    required this.edits,
    required this.saving,
    required this.valid,
    required this.onChanged,
    required this.onSave,
  });

  final List<Student> roster;
  final Map<String, num> saved;
  final Map<String, String> edits;
  final bool saving;
  final bool Function(String) valid;
  final void Function(String id, String value) onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    if (roster.isEmpty) {
      return const EmptyState(icon: Icons.groups_outlined, title: 'Grupta öğrenci yok');
    }
    return Scaffold(
      floatingActionButton: edits.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Text('Kaydet'),
            ),
      body: ListView.separated(
        padding: const EdgeInsets.only(top: 8, bottom: 96),
        itemCount: roster.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, i) {
          final s = roster[i];
          final initial = saved[s.id] == null ? '' : formatNumber(saved[s.id]!);
          final current = edits[s.id] ?? initial;
          return ContentWidth(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Text(s.fullName)),
                  NumberBox(
                    key: ValueKey(s.id),
                    initial: initial,
                    label: 'Not',
                    width: 80,
                    decimal: true,
                    error: !valid(current),
                    onChanged: (v) => onChanged(s.id, v),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
