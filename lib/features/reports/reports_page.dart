import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons.dart';
import '../../core/session.dart';
import '../../data/reports_repository.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../academics/academic_widgets.dart';
import '../academics/ranking.dart';
import '../share/share_table.dart';
import 'my_students_page.dart';
import 'report_logic.dart';
import 'report_widgets.dart';

/// Yönetici: yurt geneli raporlar, modül bazında en iyi / en zayıf öğrenciler.
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  late final RangeState _r = RangeState(session.ctx.today);
  String? _group;

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(reportProvider(_r.range));
    final modules = (ref.watch(modulesProvider).value ?? const <DormModule>[]).where((m) => m.isActive).toList();
    final scope = myScope(ref, _group);
    final groupName = scope.groups.where((g) => g.id == _group).firstOrNull?.name;

    return Scaffold(
      appBar: AppBar(title: const Text('Raporlar')),
      body: Column(
        children: [
          RangeBar(preset: _r.preset, range: _r.range, onChanged: (p, r) => setState(() {
                _r.preset = p;
                _r.range = r;
              })),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ContentWidth(
              child: DropdownButtonFormField<String?>(
                initialValue: _group,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(isDense: true, labelText: 'Kapsam'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Tüm yurt')),
                  for (final g in scope.groups) DropdownMenuItem<String?>(value: g.id, child: Text('${g.name} (${g.kind.label})')),
                ],
                onChanged: (v) => setState(() => _group = v),
              ),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: report,
              onRetry: () => ref.invalidate(reportProvider(_r.range)),
              builder: (data) {
                final students = scope.students;
                if (students.isEmpty) return const EmptyState(icon: Icons.groups_outlined, title: 'Öğrenci yok');
                final generals = [for (final s in students) ?generalScore(data[s.id], modules)];
                final attendance = modules.where((m) => m.code == 'attendance').firstOrNull;
                final attValues = attendance == null
                    ? const <double>[]
                    : [for (final s in students) ?data[s.id]?[attendance.id]?.percent];
                final totalRecords = students.fold<int>(0, (a, s) => a + (data[s.id]?.values.fold<int>(0, (b, c) => b + c.count) ?? 0));

                void openRanking(DormModule? m) => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RankingPage(module: m, students: students, report: data, modules: modules, range: _r.range, scopeName: groupName),
                    ));

                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(reportProvider(_r.range)),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      ContentWidth(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            StatsBar(items: [
                              ('Öğrenci', '${students.length}'),
                              ('Genel ortalama', formatPercent(Stats.of(generals).average)),
                              if (attendance != null) ('Yoklama ort.', formatPercent(Stats.of(attValues).average)),
                              ('Toplam kayıt', '$totalRecords'),
                            ]),
                            const SizedBox(height: 16),
                            _TopBottomCard(
                              title: 'Genel Başarı',
                              icon: Icons.emoji_events_outlined,
                              result: rankStudents(students: students, report: data, modules: modules),
                              valueLabel: (e) => formatPercent(e.value),
                              onMore: () => openRanking(null),
                            ),
                            for (final m in modules) ...[
                              const SizedBox(height: 12),
                              _TopBottomCard(
                                title: m.name,
                                icon: moduleIcon(m.icon),
                                result: rankStudents(students: students, report: data, modules: modules, module: m),
                                valueLabel: (e) => m.valueType == ModuleValueType.book ? '${e.value.toInt()} kitap' : formatPercent(e.value),
                                onMore: () => openRanking(m),
                              ),
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
}

class _TopBottomCard extends StatelessWidget {
  const _TopBottomCard({required this.title, required this.icon, required this.result, required this.valueLabel, required this.onMore});

  final String title;
  final IconData icon;
  final ({List<Ranked<RankEntry>> ranked, int minCount, int excluded}) result;
  final String Function(RankEntry) valueLabel;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final ranked = result.ranked;
    const n = 5;
    final top = ranked.take(n).toList();
    final bottom = ranked.length > n ? ranked.reversed.take(n.clamp(0, ranked.length - n)).toList() : <Ranked<RankEntry>>[];

    Widget column(String label, List<Ranked<RankEntry>> list, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 4),
              for (final r in list)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(width: 22, child: Text('${r.rank}.', style: Theme.of(context).textTheme.bodySmall)),
                      Expanded(child: Text(r.item.student.fullName, overflow: TextOverflow.ellipsis)),
                      Text(valueLabel(r.item), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                TextButton(onPressed: ranked.isEmpty ? null : onMore, child: const Text('Tümü')),
              ],
            ),
            if (ranked.isEmpty)
              Text('Bu aralıkta veri yok', style: Theme.of(context).textTheme.bodySmall)
            else
              LayoutBuilder(builder: (context, c) {
                final wide = c.maxWidth > 520;
                final topCol = column('En iyiler', top, const Color(0xFF2E7D32));
                final bottomCol = bottom.isEmpty ? null : column('En zayıflar', bottom, const Color(0xFFC62828));
                if (wide) {
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [topCol, if (bottomCol != null) ...[const SizedBox(width: 16), bottomCol]]);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [Row(children: [topCol]), if (bottomCol != null) ...[const SizedBox(height: 8), Row(children: [bottomCol])]],
                );
              }),
            if (result.excluded > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Text(
                  '${result.excluded} öğrenci az kayıt nedeniyle (${result.minCount} kayıttan az) sıralamaya alınmadı.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Modül (veya genel başarı) için tam sıralama, paylaşılabilir.
class RankingPage extends StatelessWidget {
  const RankingPage({
    super.key,
    required this.module,
    required this.students,
    required this.report,
    required this.modules,
    required this.range,
    this.scopeName,
  });

  final DormModule? module;
  final List<Student> students;
  final StudentReport report;
  final List<DormModule> modules;
  final DateRange range;
  final String? scopeName;

  @override
  Widget build(BuildContext context) {
    final m = module;
    final title = m?.name ?? 'Genel Başarı';
    final result = rankStudents(students: students, report: report, modules: modules, module: m);
    final isBook = m?.valueType == ModuleValueType.book;
    String value(RankEntry e) => isBook ? '${e.value.toInt()}' : formatPercent(e.value);
    String detail(RankEntry e) => m == null ? '${e.count} kayıt' : cellDetail(m, report[e.student.id]?[m.id]);

    ShareTable table() => ShareTable(
          title: '$title Sıralaması',
          subtitle: [scopeName ?? 'Tüm yurt', rangeLabel(range)].join(' · '),
          columns: ['Sıra', 'Öğrenci', 'Ayrıntı', isBook ? 'Kitap' : 'Başarı'],
          numericFrom: 3,
          rows: [
            for (final r in result.ranked)
              ShareRow(studentId: r.item.student.id, cells: ['${r.rank}', r.item.student.fullName, detail(r.item), value(r.item)]),
          ],
          footer: result.excluded > 0 ? '${result.minCount} kayıttan az verisi olan ${result.excluded} öğrenci listeye alınmadı' : null,
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [IconButton(tooltip: 'Paylaş', onPressed: () => openSharePreview(context, table()), icon: const Icon(Icons.share))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text([scopeName ?? 'Tüm yurt', rangeLabel(range)].join(' · '), style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (final r in result.ranked)
                        ListTile(
                          leading: RankBadge(r.rank),
                          title: Text(r.item.student.fullName),
                          subtitle: Text(detail(r.item)),
                          trailing: Text(
                            isBook ? '${value(r.item)} kitap' : value(r.item),
                            style: TextStyle(fontWeight: FontWeight.w700, color: isBook ? null : percentColor(r.item.value)),
                          ),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => StudentReportPage(student: r.item.student, range: range),
                          )),
                        ),
                    ],
                  ),
                ),
                if (result.excluded > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${result.excluded} öğrenci ${result.minCount} kayıttan az verisi olduğu için listede yok.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
