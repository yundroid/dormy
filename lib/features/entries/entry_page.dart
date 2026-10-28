import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/icons.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/dashboard_repository.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'entry_logic.dart';

/// Tüm "giriş" tipli modüller için ortak veri giriş ekranı
/// (yoklama, yatak-dolap, etüt, dahili ders ve yurda özel modüller).
class EntryPage extends ConsumerStatefulWidget {
  const EntryPage({super.key, required this.moduleId});

  final String moduleId;

  @override
  ConsumerState<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends ConsumerState<EntryPage> {
  late DateTime _date = session.ctx.today;
  int _session = 0;
  bool _sessionPicked = false;
  String _search = '';
  String? _groupFilter;
  final Map<String, Object?> _changes = {};
  bool _saving = false;

  EntryKey get _key => (moduleId: widget.moduleId, date: _date);

  Future<bool> _confirmDiscard() async {
    if (_changes.isEmpty) return true;
    return confirm(
      context,
      title: 'Kaydedilmemiş değişiklikler',
      message: '${_changes.length} öğrenci için yaptığınız değişiklikler kaydedilmedi. Vazgeçilsin mi?',
      confirmLabel: 'Vazgeç ve devam et',
      destructive: true,
    );
  }

  Future<void> _changeDate(DateTime d) async {
    if (dateOnly(d) == _date) return;
    if (!await _confirmDiscard()) return;
    setState(() {
      _date = dateOnly(d);
      _changes.clear();
      _sessionPicked = false;
    });
  }

  Future<void> _changeSession(int s) async {
    if (s == _session) return;
    if (!await _confirmDiscard()) return;
    setState(() {
      _session = s;
      _sessionPicked = true;
      _changes.clear();
    });
  }

  Future<void> _pickDate() async {
    final ctx = session.ctx;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: ctx.earliestEntryDate ?? DateTime(ctx.today.year - 2),
      lastDate: ctx.today,
    );
    if (picked != null) await _changeDate(picked);
  }

  Future<void> _save(DormModule module) async {
    setState(() => _saving = true);
    final ok = await runAction(
      context,
      () => Repo.saveEntries(module: module, date: _date, sessionIndex: _session, changes: Map.of(_changes)),
      success: 'Kaydedildi',
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _changes.clear();
    });
    if (ok) {
      ref.invalidate(entriesProvider(_key));
      ref.invalidate(todayProgressProvider);
      ref.invalidate(attendanceAlertsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final modules = ref.watch(modulesProvider);
    return AsyncView(
      value: modules,
      builder: (all) {
        final module = all.where((m) => m.id == widget.moduleId).firstOrNull;
        if (module == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Modül bulunamadı'));
        }
        return _buildForModule(module);
      },
    );
  }

  Widget _buildForModule(DormModule module) {
    final studentsAsync = ref.watch(moduleStudentsProvider(module.id));
    final entriesAsync = ref.watch(entriesProvider(_key));

    final entries = entriesAsync.value;
    // İlk açılışta, henüz tamamlanmamış ilk vakti seç.
    if (!_sessionPicked && entries != null && studentsAsync.hasValue && module.sessions.length > 1) {
      final total = studentsAsync.value!.length;
      _session = firstIncompleteSession(module.sessions.length, entries, total);
      _sessionPicked = true;
    }

    return PopScope(
      canPop: _changes.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) {
          _changes.clear();
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Icon(moduleIcon(module.icon)),
              const SizedBox(width: 8),
              Expanded(child: Text(module.name, overflow: TextOverflow.ellipsis)),
            ],
          ),
          actions: [
            if (studentsAsync.hasValue && entries != null) _bulkMenu(module, studentsAsync.value!, entries),
          ],
        ),
        floatingActionButton: _changes.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: _saving ? null : () => _save(module),
                icon: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text('Kaydet (${_changes.length})'),
              ),
        body: Column(
          children: [
            _DateBar(date: _date, onSelect: _changeDate, onPickMore: _pickDate),
            if (module.sessions.length > 1)
              _SessionBar(
                sessions: module.sessions,
                selected: _session,
                entries: entries ?? const [],
                total: studentsAsync.value?.length ?? 0,
                onSelect: _changeSession,
              ),
            Expanded(
              child: AsyncView(
                value: studentsAsync,
                onRetry: () => ref.invalidate(moduleStudentsProvider(module.id)),
                builder: (students) => AsyncView(
                  value: entriesAsync,
                  onRetry: () => ref.invalidate(entriesProvider(_key)),
                  builder: (entries) => _buildList(module, students, entries),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, Object?> _savedValues(List<Entry> entries) => {
        for (final e in entries.where((e) => e.session == _session)) e.studentId: e.choice ?? e.value,
      };

  Widget _bulkMenu(DormModule module, List<ModuleStudent> students, List<Entry> entries) {
    final options = valueOptions(module);
    if (options.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<Object>(
      tooltip: 'Toplu işlem',
      icon: const Icon(Icons.playlist_add_check),
      itemBuilder: (_) => [
        for (final o in options) PopupMenuItem(value: o.value, child: Text('Boş olanları "${o.label}" yap')),
      ],
      onSelected: (value) {
        final saved = _savedValues(entries);
        setState(() {
          for (final s in _filtered(students)) {
            final current = _changes.containsKey(s.studentId) ? _changes[s.studentId] : saved[s.studentId];
            if (current == null) _changes[s.studentId] = value;
          }
        });
      },
    );
  }

  List<ModuleStudent> _filtered(List<ModuleStudent> students) {
    final q = _search.trim().toLowerCase();
    return students.where((s) {
      if (_groupFilter != null && s.groupId != _groupFilter) return false;
      if (q.isEmpty) return true;
      return s.fullName.toLowerCase().contains(q) || (s.roomNo?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Widget _buildList(DormModule module, List<ModuleStudent> students, List<Entry> entries) {
    if (students.isEmpty) {
      return EmptyState(
        icon: Icons.groups_outlined,
        title: 'Listede öğrenci yok',
        message: module.scope == ModuleScope.general
            ? 'Yönetim panelinden öğrenci ekleyin.'
            : 'Grubunuza henüz öğrenci atanmamış.',
      );
    }
    final saved = _savedValues(entries);
    final groups = <String, String>{
      for (final s in students)
        if (s.groupId != null) s.groupId!: s.groupName ?? '',
    };
    final filtered = _filtered(students);
    final summary = summarize(module, [for (final s in students) _changes.containsKey(s.studentId) ? _changes[s.studentId] : saved[s.studentId]]);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: ContentWidth(
            child: Column(
              children: [
                TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Öğrenci adı veya oda no ara',
                  ),
                ),
                if (groups.length > 1)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Tümü'),
                          selected: _groupFilter == null,
                          onSelected: (_) => setState(() => _groupFilter = null),
                        ),
                        for (final g in groups.entries) ...[
                          const SizedBox(width: 6),
                          ChoiceChip(
                            label: Text(g.value),
                            selected: _groupFilter == g.key,
                            onSelected: (_) => setState(() => _groupFilter = g.key),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                _SummaryRow(summary: summary, total: students.length),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (context, i) {
              final s = filtered[i];
              final changed = _changes.containsKey(s.studentId);
              final value = changed ? _changes[s.studentId] : saved[s.studentId];
              return ContentWidth(
                child: _StudentRow(
                  key: ValueKey('${s.studentId}-${isoDate(_date)}-$_session'),
                  student: s,
                  module: module,
                  value: value,
                  changed: changed,
                  onChanged: (v) => setState(() {
                    if (v == saved[s.studentId]) {
                      _changes.remove(s.studentId);
                    } else {
                      _changes[s.studentId] = v;
                    }
                  }),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _DateBar extends StatelessWidget {
  const _DateBar({required this.date, required this.onSelect, required this.onPickMore});

  final DateTime date;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onPickMore;

  @override
  Widget build(BuildContext context) {
    final ctx = session.ctx;
    final days = [for (var i = 0; i <= ctx.backfillDays; i++) ctx.today.subtract(Duration(days: i))];
    final isOlder = !days.contains(date);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            for (final d in days) ...[
              ChoiceChip(
                label: Text(relativeDayLabel(d, ctx.today)),
                selected: d == date,
                onSelected: (_) => onSelect(d),
              ),
              const SizedBox(width: 6),
            ],
            ActionChip(
              avatar: const Icon(Icons.calendar_month, size: 18),
              label: Text(isOlder ? formatDay(date) : 'Tarih seç'),
              onPressed: onPickMore,
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionBar extends StatelessWidget {
  const _SessionBar({
    required this.sessions,
    required this.selected,
    required this.entries,
    required this.total,
    required this.onSelect,
  });

  final List<String> sessions;
  final int selected;
  final List<Entry> entries;
  final int total;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final counts = sessionCounts(sessions.length, entries);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          for (var i = 0; i < sessions.length; i++) ...[
            ChoiceChip(
              avatar: total > 0 && counts[i] >= total
                  ? const Icon(Icons.check_circle, size: 18, color: StatusColors.present)
                  : null,
              label: Text(counts[i] > 0 && counts[i] < total ? '${sessions[i]} ${counts[i]}/$total' : sessions[i]),
              selected: i == selected,
              onSelected: (_) => onSelect(i),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summary, required this.total});

  final EntrySummary summary;
  final int total;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        Text('Girilen: ${summary.filled}/$total', style: style),
        const Spacer(),
        if (summary.attendance != null) ...[
          for (final c in AttendanceChoice.values) ...[
            Icon(Icons.circle, size: 10, color: attendanceColor(c)),
            const SizedBox(width: 4),
            Text('${c.label} ${summary.attendance![c] ?? 0}', style: style),
            const SizedBox(width: 10),
          ],
        ],
        if (summary.average != null) Text('Ortalama: ${summary.average!.toStringAsFixed(2)}', style: style),
      ],
    );
  }
}

Color attendanceColor(AttendanceChoice c) => switch (c) {
      AttendanceChoice.present => StatusColors.present,
      AttendanceChoice.absent => StatusColors.absent,
      AttendanceChoice.excused => StatusColors.excused,
    };

class _StudentRow extends StatelessWidget {
  const _StudentRow({
    super.key,
    required this.student,
    required this.module,
    required this.value,
    required this.changed,
    required this.onChanged,
  });

  final ModuleStudent student;
  final DormModule module;
  final Object? value;
  final bool changed;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sub = [
      if (student.roomNo != null) 'Oda ${student.roomNo}',
      if (student.groupName != null) student.groupName!,
      if (student.schoolGrade != null) student.schoolGrade!,
    ].join(' · ');
    final narrow = MediaQuery.sizeOf(context).width < 420;

    final info = Row(
      children: [
        if (changed)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(Icons.circle, size: 8, color: theme.colorScheme.primary),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(student.fullName, style: theme.textTheme.bodyLarge, overflow: TextOverflow.ellipsis),
              if (sub.isNotEmpty)
                Text(sub, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
        ),
      ],
    );
    final input = _ValueInput(module: module, value: value, onChanged: onChanged);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: narrow && module.valueType == ModuleValueType.score && (module.maxValue! - module.minValue!) > 4
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [info, const SizedBox(height: 6), input])
          : Row(children: [Expanded(child: info), const SizedBox(width: 8), input]),
    );
  }
}

class _ValueInput extends StatelessWidget {
  const _ValueInput({required this.module, required this.value, required this.onChanged});

  final DormModule module;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    switch (module.valueType) {
      case ModuleValueType.attendance:
        final selected = value is String ? AttendanceChoice.parse(value as String) : null;
        return SegmentedButton<AttendanceChoice>(
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          segments: [
            for (final c in AttendanceChoice.values)
              ButtonSegment(
                value: c,
                label: Text(c == AttendanceChoice.excused ? 'İzin' : c.label,
                    style: TextStyle(
                      color: selected == c ? attendanceColor(c) : null,
                      fontWeight: selected == c ? FontWeight.bold : null,
                    )),
              ),
          ],
          selected: {?selected},
          onSelectionChanged: (s) => onChanged(s.isEmpty ? null : s.first.name),
        );
      case ModuleValueType.yesNo:
        final selected = value is num ? (value as num).toInt() : null;
        return SegmentedButton<int>(
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          segments: const [
            ButtonSegment(value: 1, label: Text('Evet')),
            ButtonSegment(value: 0, label: Text('Hayır')),
          ],
          selected: {?selected},
          onSelectionChanged: (s) => onChanged(s.isEmpty ? null : s.first),
        );
      default:
        final min = module.minValue!, max = module.maxValue!;
        final current = value is num ? (value as num) : null;
        if (max - min <= 9) {
          return Wrap(
            spacing: 4,
            children: [
              for (var v = min; v <= max; v++) _ScoreDot(value: v, selected: current == v, onTap: () => onChanged(current == v ? null : v)),
            ],
          );
        }
        return SizedBox(
          width: 90,
          child: TextFormField(
            initialValue: current?.toString() ?? '',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            decoration: InputDecoration(isDense: true, hintText: '$min-$max'),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (t) {
              final n = int.tryParse(t ?? '');
              if (t == null || t.isEmpty) return null;
              return n == null || n < min || n > max ? '$min-$max' : null;
            },
            onChanged: (t) {
              final n = int.tryParse(t);
              if (t.isEmpty) {
                onChanged(null);
              } else if (n != null && n >= min && n <= max) {
                onChanged(n);
              }
            },
          ),
        );
    }
  }
}

class _ScoreDot extends StatelessWidget {
  const _ScoreDot({required this.value, required this.selected, required this.onTap});

  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? scheme.primary : null,
          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant),
        ),
        child: Text(
          '$value',
          style: TextStyle(color: selected ? scheme.onPrimary : scheme.onSurface, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
