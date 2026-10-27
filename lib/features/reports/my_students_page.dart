import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session.dart';
import '../../core/supabase.dart';
import '../../data/reports_repository.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../academics/ranking.dart';
import '../share/share_table.dart';
import 'report_logic.dart';
import 'report_widgets.dart';

/// Rapor sayfaları arasında paylaşılan tarih aralığı seçimi
class RangeState {
  RangeState(DateTime today) : range = rangeFor(RangePreset.thisMonth, today);

  RangePreset preset = RangePreset.thisMonth;
  DateRange range;
}

/// Öğretmenin grupları (etüt + dahili) ve öğrencileri; admin için tüm gruplar ve öğrenciler.
({List<Group> groups, List<Student> students}) myScope(WidgetRef ref, String? groupId) {
  final groups = ref.watch(groupsProvider).value ?? const <Group>[];
  final teachers = ref.watch(groupTeachersProvider).value ?? const <String, Set<String>>{};
  final memberships = ref.watch(membershipsProvider).value ?? const <Membership>[];
  final students = ref.watch(studentsProvider).value ?? const <Student>[];
  final isAdmin = session.ctx.isAdmin;

  final myGroups = groups
      .where((g) => !g.isArchived && (isAdmin || (teachers[g.id]?.contains(currentUserId) ?? false)))
      .toList()
    ..sort((a, b) => a.kind != b.kind ? a.kind.index.compareTo(b.kind.index) : a.name.compareTo(b.name));
  final groupIds = groupId != null ? {groupId} : myGroups.map((g) => g.id).toSet();
  final inGroups = memberships.where((m) => groupIds.contains(m.groupId)).map((m) => m.studentId).toSet();
  final list = students
      .where((s) => s.status == StudentStatus.active && ((isAdmin && groupId == null) || inGroups.contains(s.id)))
      .toList()
    ..sort((a, b) => a.fullName.compareTo(b.fullName));
  return (groups: myGroups, students: list);
}

class MyStudentsPage extends ConsumerStatefulWidget {
  const MyStudentsPage({super.key});

  @override
  ConsumerState<MyStudentsPage> createState() => _MyStudentsPageState();
}

class _MyStudentsPageState extends ConsumerState<MyStudentsPage> {
  late final RangeState _r = RangeState(session.ctx.today);
  String? _group;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(reportProvider(_r.range));
    final modules = (ref.watch(modulesProvider).value ?? const <DormModule>[]).where((m) => m.isActive).toList();
    final scope = myScope(ref, _group);
    final groupName = scope.groups.where((g) => g.id == _group).firstOrNull?.name;

    return Scaffold(
      appBar: AppBar(title: const Text('Öğrencilerim')),
      body: Column(
        children: [
          RangeBar(preset: _r.preset, range: _r.range, onChanged: (p, r) => setState(() {
                _r.preset = p;
                _r.range = r;
              })),
          if (scope.groups.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text(session.ctx.isAdmin ? 'Tüm öğrenciler' : 'Tüm gruplarım'),
                    selected: _group == null,
                    onSelected: (_) => setState(() => _group = null),
                  ),
                  for (final g in scope.groups) ...[
                    const SizedBox(width: 6),
                    ChoiceChip(label: Text(g.name), selected: _group == g.id, onSelected: (_) => setState(() => _group = g.id)),
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ContentWidth(
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Öğrenci ara'),
              ),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: report,
              onRetry: () => ref.invalidate(reportProvider(_r.range)),
              builder: (data) {
                final q = _search.trim().toLowerCase();
                final list = scope.students.where((s) => q.isEmpty || s.fullName.toLowerCase().contains(q)).toList();
                if (scope.students.isEmpty) {
                  return EmptyState(
                    icon: Icons.groups_outlined,
                    title: 'Öğrenci yok',
                    message: session.ctx.isAdmin ? null : 'Size atanmış bir etüt veya dahili ders grubu bulunmuyor.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(reportProvider(_r.range)),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      ContentWidth(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text('${list.length} öğrenci', style: Theme.of(context).textTheme.titleSmall)),
                                FilledButton.tonalIcon(
                                  onPressed: () => openSharePreview(
                                    context,
                                    _listTable(scope.students, data, modules, groupName),
                                  ),
                                  icon: const Icon(Icons.share, size: 18),
                                  label: const Text('Listeyi paylaş'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (final s in list) ...[
                              _StudentCard(
                                student: s,
                                cells: data[s.id],
                                modules: modules,
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => StudentReportPage(student: s, range: _r.range),
                                )),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  ShareTable _listTable(List<Student> students, StudentReport data, List<DormModule> modules, String? groupName) {
    final cols = modules.where((m) => students.any((s) => data[s.id]?[m.id] != null)).toList();
    final rows = rankBy(students, (s) => generalScore(data[s.id], modules) ?? -1, tieBreak: (s) => s.fullName);
    return ShareTable(
      title: 'Öğrenci Durum Raporu',
      subtitle: [?groupName, rangeLabel(_r.range)].join(' · '),
      columns: ['Sıra', 'Öğrenci', for (final m in cols) m.name, 'Genel'],
      rows: [
        for (final r in rows)
          ShareRow(studentId: r.item.id, cells: [
            generalScore(data[r.item.id], modules) == null ? '-' : '${r.rank}',
            r.item.fullName,
            for (final m in cols)
              m.valueType == ModuleValueType.book
                  ? '${data[r.item.id]?[m.id]?.count ?? 0} kitap'
                  : formatPercent(data[r.item.id]?[m.id]?.percent),
            formatPercent(generalScore(data[r.item.id], modules)),
          ]),
      ],
      footer: 'Yüzdeler seçilen tarih aralığındaki kayıtlardan hesaplanır',
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.student, required this.cells, required this.modules, required this.onTap});

  final Student student;
  final Map<String, ReportCell>? cells;
  final List<DormModule> modules;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final general = generalScore(cells, modules);
    final withData = modules.where((m) => cells?[m.id] != null).toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ScoreCircle(percent: general, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(student.fullName, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    if (withData.isEmpty)
                      Text('Bu aralıkta kayıt yok', style: Theme.of(context).textTheme.bodySmall)
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final m in withData)
                            _MiniChip(
                              label: m.name,
                              value: m.valueType == ModuleValueType.book
                                  ? '${cells![m.id]!.count}'
                                  : formatPercent(cells![m.id]!.percent),
                              color: m.valueType == ModuleValueType.book ? Colors.blueGrey : percentColor(cells![m.id]!.percent),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text('$label $value', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

// ---------------------------------------------------------------------------

/// Tek öğrencinin karnesi (veliye paylaşılabilir)
class StudentReportPage extends ConsumerStatefulWidget {
  const StudentReportPage({super.key, required this.student, required this.range});

  final Student student;
  final DateRange range;

  @override
  ConsumerState<StudentReportPage> createState() => _StudentReportPageState();
}

class _StudentReportPageState extends ConsumerState<StudentReportPage> {
  late final RangeState _r = RangeState(session.ctx.today)..range = widget.range;

  @override
  void initState() {
    super.initState();
    _r.preset = RangePreset.values.firstWhere(
      (p) => p != RangePreset.custom && rangeFor(p, session.ctx.today) == widget.range,
      orElse: () => RangePreset.custom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
    final report = ref.watch(reportProvider(_r.range));
    final modules = (ref.watch(modulesProvider).value ?? const <DormModule>[]).where((m) => m.isActive).toList();
    final groups = ref.watch(groupsProvider).value ?? const <Group>[];
    final memberships = ref.watch(membershipsProvider).value ?? const <Membership>[];
    final myGroups = [
      for (final m in memberships.where((m) => m.studentId == s.id)) ?groups.where((g) => g.id == m.groupId).firstOrNull?.name,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(s.fullName)),
      body: Column(
        children: [
          RangeBar(preset: _r.preset, range: _r.range, onChanged: (p, r) => setState(() {
                _r.preset = p;
                _r.range = r;
              })),
          Expanded(
            child: AsyncView(
              value: report,
              onRetry: () => ref.invalidate(reportProvider(_r.range)),
              builder: (data) {
                final cells = data[s.id];
                final general = generalScore(cells, modules);
                final info = [if (s.roomNo != null) 'Oda ${s.roomNo}', if (s.schoolGrade != null) s.schoolGrade!, ...myGroups].join(' · ');

                ShareTable table() => ShareTable(
                      title: '${s.fullName} · Gelişim Raporu',
                      subtitle: [if (info.isNotEmpty) info, rangeLabel(_r.range)].join(' · '),
                      columns: const ['Kontrol', 'Ayrıntı', 'Başarı'],
                      nameColumn: -1,
                      numericFrom: 2,
                      rows: [
                        for (final m in modules)
                          ShareRow(cells: [
                            m.name,
                            cellDetail(m, cells?[m.id]),
                            m.valueType == ModuleValueType.book ? '${cells?[m.id]?.count ?? 0} kitap' : formatPercent(cells?[m.id]?.percent),
                          ]),
                        ShareRow(cells: ['GENEL BAŞARI', 'Modül ağırlıklarına göre', formatPercent(general)]),
                      ],
                      footer: 'Yüzdeler seçilen tarih aralığındaki kayıtlardan hesaplanır',
                    );

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ContentWidth(
                      maxWidth: 700,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  ScoreCircle(percent: general, size: 76),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Genel başarı', style: Theme.of(context).textTheme.titleMedium),
                                        if (info.isNotEmpty) Text(info, style: Theme.of(context).textTheme.bodySmall),
                                        if (s.guardianName != null || s.guardianPhone != null)
                                          Text('Veli: ${[s.guardianName, s.guardianPhone].whereType<String>().join(' · ')}',
                                              style: Theme.of(context).textTheme.bodySmall),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                                for (final m in modules) _ModuleRow(module: m, cell: cells?[m.id]),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Genel başarı; rapora dahil modüllerin yüzdelerinin, modül ağırlıklarıyla ortalamasıdır. '
                            'Verisi olmayan modüller hesaba katılmaz. Yoklamada izinli günler sayılmaz.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({required this.module, required this.cell});

  final DormModule module;
  final ReportCell? cell;

  @override
  Widget build(BuildContext context) {
    final isBook = module.valueType == ModuleValueType.book;
    return ListTile(
      title: Row(
        children: [
          Expanded(child: Text(module.name)),
          Text(
            isBook ? '${cell?.count ?? 0} kitap' : formatPercent(cell?.percent),
            style: TextStyle(fontWeight: FontWeight.w700, color: isBook ? null : percentColor(cell?.percent)),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isBook) ...[const SizedBox(height: 6), PercentBar(percent: cell?.percent)],
          const SizedBox(height: 4),
          Text(cellDetail(module, cell)),
        ],
      ),
    );
  }
}
